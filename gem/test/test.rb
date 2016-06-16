require 'simplecov'
SimpleCov.start

require 'test/unit'
require 'vagrantworld'

require 'time'
require 'net/http'
require 'json'
require 'pp'

# These tests are integration tests, technically, because they rely on a vault instance
# running locally.

# There is no easy way to determine the maximum lease duration in vault, so tell us here:
LEASE_DURATION = '5m'.freeze
LEASE_MAX = '30m'.freeze

# Similarly, tell us where the file with a valid vault token is
TOKEN_LOCATION = '../docker-provision/vault-tokens/root.token'.freeze

# An integration test for simple operations on Vault.
class VaultTest < Test::Unit::TestCase
  def test_health_check
    vault = Vagrantworld::Vault.new('http://localhost:8200', `cat #{TOKEN_LOCATION}`)
    health = vault.health
    assert_not_nil(health['initialized'])
  end

  def test_create_revoke
    vault = Vagrantworld::Vault.new('http://localhost:8200', `cat #{TOKEN_LOCATION}`)
    cred = vault.get_credential('mysql', 'readonly')
    assert(cred.expiration_time > Time.now, 'Lease expired in the past!')
    result = vault.revoke_credential(cred)
    assert_equal(204, result, "Revocation returned an error #{result}")
  end

  def test_renew
    vault_host = Net::HTTP.new('localhost', 8200)
    vault = Vagrantworld::Vault.new('http://localhost:8200', `cat #{TOKEN_LOCATION}`)

    # Artificially shorten lease durations for testing
    vault_host.post('/v1/mysql/config/lease', JSON.generate(
      lease: '5s',
      lease_max: '20s'
    ), 'X-Vault-Token' => `cat #{TOKEN_LOCATION}`)

    cred = vault.get_credential('mysql', 'readonly') do |cd, extended|
      cred = cd unless extended
    end
    time_until = cred.lease_duration
    sleep(time_until + 10)
    result = vault.revoke_credential(cred)
    assert_equal(204, result, "Revocation returned an error #{result}")

    # Reset the lease duration now that we're done
    vault_host.post('/v1/mysql/config/lease', JSON.generate(
      lease: LEASE_DURATION,
      lease_max: LEASE_MAX
    ), 'X-Vault-Token' => `cat #{TOKEN_LOCATION}`)
  end
end

# An integration test for simple operations on Consul
class ConsulTest < Test::Unit::TestCase
  def test_create_read_destroy_simple_service
    consul = Vagrantworld::Consul.new('http://localhost:8500')
    consul.simple_register('service', 'host', 24601)

    # Verify our service data
    service_data = consul.service('service')[0]
    assert_equal(service_data['ServicePort'], 24601)
    assert_equal(service_data['Node'], 'service')
    assert_equal(service_data['ServiceAddress'], 'host')

    # Verify our node data
    node_data = consul.node('service')
    assert_equal(node_data['Node']['Node'], 'service')
    assert_not_nil(node_data['Services'])

    # Verify the service exists in the services hash
    services_data = consul.services
    assert_not_nil(services_data['service'])

    # Verify the node exists in the node hash
    nodes_data = consul.nodes
    found = nodes_data.detect { |v| v['Node'] == 'service' }
    assert_not_nil(found)

    consul.simple_deregister('service')
    service_data = consul.service('service')
    # Should be no service with that name.
    assert_equal(0, service_data.length, 'Should have had a service list of size zero!')
  end
end
