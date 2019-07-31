require 'json'
require_relative 'lib/staking_balance_checker'

def staking_balance_check(event:, context:)
  begin
    StakingBalanceChecker.run
    { statusCode: 200, body: JSON.generate('success!') }
  rescue => e
    { statusCode: 500, body: JSON.generate(e) }
  end
end
