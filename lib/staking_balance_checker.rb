require 'uri'
require 'net/http'

class StakingBalanceChecker
  ENDPOINT = 'https://stargate.cosmos.network/staking/validators'
  STATUSES = ['bonded', 'unbonding', 'unbonded']

  def initialize
  end

  def run
    data = extract_all
    data = transform(data)
    load_to_s3(data)
  end

  def extract_all
    STATUSES.map {|status| extract(status) }
  end

  def extract(status)
    res = Net::HTTP.get_response(url_for(status))
    raise unless res.code == '200'

    JSON.parse(res.body)
  end

  def transform(data)
    data.sort_by {|d| -d['tokens'] }.map.with_index(1) {|d, i|
      {
        moniker: d['description']['moniker'],
        delegated_balance: d['tokens'],
        rank: i,
        status: status_to_s(d['status'])
      }
    }
  end

  def load_to_s3(data)

  end

  def url_for(status)
    url = URI.parse(ENDPOINT)
    url.query = "status=#{status}"
    url
  end

  def status_to_s(status)
    case status
    when 0 then 'unbonded'
    when 1 then 'unbonding'
    when 2 then 'bonded'
    else raise ArgumentError('unknown status')
    end
  end
end
