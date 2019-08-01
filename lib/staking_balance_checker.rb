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

  def initialize
    @s3_cli = Aws::S3::Client.new

    @first_run = true unless last_updated_at
  end

  def run
    data = extract_all
    result = transform(data)
    load_to_s3(result)
    notify(result)
  end

  def extract_all
    STATUSES.flat_map {|status| extract(status) }
  end

  def extract(status)
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

    data =
      raw_data.sort_by {|d| -(d['tokens'].to_i) }.map {|d|
        rank = rank_acc.call if d['status'] == 2

        {
          'moniker'                  => d['description']['moniker'],
          'address'                  => d['operator_address'],
          'status'                   => status_to_s(d['status']),
          'delegated_balance'        => d['tokens'],
          'delegated_balance_change' => delegated_balance_change(d['operator_address'], d['tokens']),
          'rank'                     => rank,
          'rank_change'              => rank_change(d['operator_address'], rank)
        }
      }

    {
      'data'             => data,
      'executed_at'      => now,
      'last_executed_at' => last_updated_at
    }
  end

  def rank_change(address, this_time_rank)
    return nil if @first_run
    return nil unless this_time_rank

    last_data = find_validators_data_from(last_result, address)
    return nil unless last_data

    last_data['rank'] - this_time_rank
  end

  def delegated_balance_change(address, this_time_balance)
    return nil if @first_run
    return nil unless this_time_balance

    last_data = find_validators_data_from(last_result, address)
    return nil unless last_data

    this_time_balance.to_i - last_data['delegated_balance'].to_i
  end

  def find_validators_data_from(result, address)
    result['data'].find {|h| h['address'] == address }
  end

  def last_result
    raise if @first_run
    return @last_result if @last_result

    body = @s3_cli.get_object(bucket: ENV['BUCKET_NAME'], key: last_updated_at).body.read
    @last_result = JSON.parse(body)
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

  def last_updated_at
    return nil if @first_run
    return @last_updated_at if @last_updated_at

    begin
      @last_updated_at = @s3_cli.get_object(bucket: ENV['BUCKET_NAME'], key: KEY_LAST_UPDATED_AT).body.read
    rescue Aws::S3::Errors::NoSuchKey
      nil
    end
  end

  def load_to_s3(result)
    @s3_cli.put_object(bucket: ENV['BUCKET_NAME'], key: KEY_LAST_UPDATED_AT, body: now)
    @s3_cli.put_object(bucket: ENV['BUCKET_NAME'], key: now, body: result.to_json)
  end

  def notify(result)
    uri  = URI.parse(ENV['SLACK_ENDPOINT'])
    params = { channel: '#test', text: result.to_json }
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.start do
      request = Net::HTTP::Post.new(uri.path)
      request.set_form_data(payload: params.to_json)
      http.request(request)
    end
  end
end
