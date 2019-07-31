require 'uri'
require 'net/http'

class StakingBalanceChecker
  ENDPOINT = 'https://stargate.cosmos.network/staking/validators'

  def initialize
  end

  def url_for(status)
    url = URI.parse(ENDPOINT)
    url.query = "status=#{status}"
    url
  end
end
