require 'minitest/autorun'

require_relative '../lib/staking_balance_checker'

class Test < Minitest::Test
  def setup
    @checker = StakingBalanceChecker.new
  end

  def test_url_for_when_status_is_bonded
    assert_equal URI.parse('https://stargate.cosmos.network/staking/validators?status=bonded'), @checker.url_for('bonded')
  end
end
