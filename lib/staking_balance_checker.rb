require 'uri'
require 'net/http'
require 'aws-sdk-s3'

class StakingBalanceChecker
  ENDPOINT = 'https://stargate.cosmos.network/staking/validators'
  STATUSES = ['bonded', 'unbonding', 'unbonded']

  KEY_LAST_UPDATED_AT = 'last_updated_at'

  class << self
    def run
      self.new.run
    end
  end

  def initialize()
    @s3_cli = Aws::S3::Client.new
  end

  def run
    preprocess

    data = extract
    result = transform(data)
    load_to_s3(result)
    notify(result)
  end

  def preprocess
    @first_run = false

    begin
      @last_updated_at = @s3_cli.get_object(bucket: ENV['BUCKET_NAME'], key: KEY_LAST_UPDATED_AT).body.read
    rescue Aws::S3::Errors::NoSuchKey
      @first_run = true
      return
    end

    body = @s3_cli.get_object(bucket: ENV['BUCKET_NAME'], key: @last_updated_at).body.read
    @last_result = JSON.parse(body)
  end

  def extract
    STATUSES.flat_map {|status| extract_with_each_of(status) }
  end

  def extract_with_each_of(status)
    res = Net::HTTP.get_response(url_for(status))
    raise unless res.code == '200'

    JSON.parse(res.body)
  end

  def url_for(status)
    url = URI.parse(ENDPOINT)
    url.query = "status=#{status}"
    url
  end

  def transform(raw_data)
    n = 0
    rank_acc = -> { n += 1 }

    data = raw_data.sort_by {|d| -(d['tokens'].to_i) }.map {|d| transform_each_of(d, rank_acc) }

    {
      'data'             => data,
      'executed_at'      => now,
      'last_executed_at' => @last_updated_at || '-'
    }
  end

  def transform_each_of(raw_data, rank_acc)
    rank = rank_acc.call if raw_data['status'] == 2

    {
      'moniker'                  => raw_data['description']['moniker'],
      'address'                  => raw_data['operator_address'],
      'status'                   => status_to_s(raw_data['status']),
      'delegated_balance'        => atom_to_f(raw_data['tokens']),
      'delegated_balance_change' => delegated_balance_change(raw_data['operator_address'], raw_data['tokens']),
      'rank'                     => rank,
      'rank_change'              => rank_change(raw_data['operator_address'], rank)
    }
  end

  def rank_change(address, this_time_rank)
    return nil if @first_run
    return nil unless this_time_rank

    last_data = find_validators_data_from(@last_result, address)
    return nil unless last_data

    last_data['rank'] - this_time_rank
  end

  def delegated_balance_change(address, this_time_balance)
    return nil if @first_run
    return nil unless this_time_balance

    last_data = find_validators_data_from(@last_result, address)
    return nil unless last_data

    atom_to_f(this_time_balance.to_i - last_data['delegated_balance'].to_i)
  end

  def find_validators_data_from(result, address)
    result['data'].find {|h| h['address'] == address }
  end

  def now
    @now ||= Time.now.to_i.to_s
  end

  def status_to_s(status)
    case status
    when 0 then 'unbonded'
    when 1 then 'unbonding'
    when 2 then 'bonded'
    else raise ArgumentError('unknown status')
    end
  end

  def atom_to_f(balance)
    balance / (10 ** 6).to_f
  end

  def load_to_s3(result)
    @s3_cli.put_object(bucket: ENV['BUCKET_NAME'], key: KEY_LAST_UPDATED_AT, body: now)
    @s3_cli.put_object(bucket: ENV['BUCKET_NAME'], key: now, body: result.to_json)
  end

  def notify(result)
    uri = URI.parse(ENV['SLACK_ENDPOINT'])
    params = {
      channel: ENV['SLACK_CHANNEL'],
      text: result['data'].map {|h| text(h) }.join("\n")
    }

    puts params.to_json
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    http.start do
      request = Net::HTTP::Post.new(uri.path)
      request.set_form_data(payload: params.to_json)
      http.request(request)
    end
  end

  def text(hash)
    "##{hash['rank']} ( #{change_text(hash['rank_change'])} ) #{hash['moniker']}\t#{status_text(hash['status'])}\tdelegated_balance: #{hash['delegated_balance']}( #{change_text(hash['delegated_balance_change'])} )"
  end

  def status_text(status)
    case status
    when 'unbonded' then "#{status} :innocent:"
    when 'unbonding' then "#{status} :exploding_head:"
    when 'bonded' then "#{status} :sunglasses:"
    else raise ArgumentError('unknown status')
    end
  end

  def change_text(change)
    if change.nil? || change.zero?
      ':arrow_right:'
    elsif change.positive?
      "+#{change} :arrow_heading_up:"
    elsif change.negative?
      "#{change} :arrow_heading_down:"
    end
  end
end
