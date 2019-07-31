require 'minitest/autorun'

require_relative '../lib/staking_balance_checker'

class Test < Minitest::Test
  def setup
    @checker = StakingBalanceChecker.new
  end

  def test_url_for_when_status_is_bonded
    assert_equal URI.parse('https://stargate.cosmos.network/staking/validators?status=bonded'), @checker.url_for('bonded')
  end

  def test_transform
    data = [{
      'description' => {'moniker' => 'kansa'},
      'tokens' => 20,
      'status' => 1
    }, {
      'description' => {'moniker' => 'naska'},
      'tokens' => 5,
      'status' => 0
    }, {
      'description' => {'moniker' => 'sanka'},
      'tokens' => 100,
      'status' => 2
    }]

    expected = [
      {
        moniker: 'sanka',
        delegated_balance: 100,
        rank: 1,
        status: 'bonded'
      },{
        moniker: 'kansa',
        delegated_balance: 20,
        rank: 2,
        status: 'unbonding'
      },{
        moniker: 'naska',
        delegated_balance: 5,
        rank: 3,
        status: 'unbonded'
      }
    ]

    assert_equal expected, @checker.transform(data)
  end
end
