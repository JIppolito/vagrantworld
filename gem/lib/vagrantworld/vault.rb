require 'net/http'
require 'json'

# Vagrantworld provides classes for managing Consul/Vault/etc information.
module Vagrantworld
  # The vault api version. This is prepended to the routes.
  VAULT_VERSION = 'v1'.freeze

  # Vault is a wrapper around the Vault api that provides auth management
  class Vault
    # For auto-renewing leases, attempt to renew at 'remaining_duration' * 'RENEW_FACTOR'
    RENEW_FACTOR = 0.8

    # Create a new vault client with the provided address and token
    def initialize(address, token)
      uri = URI(address)
      @vault_host = Net::HTTP.new(uri.host, uri.port)
      @token = token
      @header = { 'X-Vault-Token' => @token }
    end

    # Return the hash version of the v1/sys/health endpoint
    def health
      JSON.parse(@vault_host.get("/#{VAULT_VERSION}/sys/health", @header).body)
    end

    # Return the mounts available through this client.
    def mounts
      JSON.parse(@vault_host.get("/#{VAULT_VERSION}/sys/mounts", @header).body)
    end

    # Accesses /v1/<mount>/creds/<role>, unless the type of the mount is
    # generic, then accesses /v1/<mount>/<role>.
    #
    # If a block is supplied, the credentials will try to be autorenewed at a
    # percentage of the lease duration based on the RENEW_FACTOR parameter.
    #
    # The parameters to the block are (credential, extended?). There are
    # three possible combinations:
    # * credential, true -- The lease was successfully renewed.
    # * credential, false -- The lease, while still active, hit maximum lease length and was replaced with a new lease.
    # * nil, false -- The lease no longer existed, due to revocation or expiry.
    #
    # Since the autorenew will not attempt to replace a lease that has already expired,
    # a client can voluntarily give up a lease early (with revoke_credential) and halt
    # the autorenew.
    def get_credential(mount, role)
      endpoint =
        if mount_type(mount) == 'generic'
          "/#{VAULT_VERSION}/#{mount}/#{role}"
        else
          "/#{VAULT_VERSION}/#{mount}/creds/#{role}"
        end
      body_hash = JSON.parse(@vault_host.get(endpoint, @header).body)
      cred = Credential.new(mount_type(mount), body_hash)

      return cred unless block_given?

      # Turn on autorenew
      Thread.new do
        # Sleep a new thread until expiry nears.
        loop do
          sleep(cred.lease_duration * RENEW_FACTOR)
          cred, extended = extend_or_replace_credential(cred, mount, role)
          yield(cred, extended)
          break if cred.nil? && !extended
        end
      end
      cred
    end

    # Attempt to extend a lease. If the lease isn't extended, instead get a
    # new lease. Return that credential and whether we were able to renew it.
    def extend_or_replace_credential(cred, mount, role)
      old_expiry = cred.expiration_time
      renew_state = renew_credential(cred)
      extended = (cred.expiration_time - old_expiry) > 0

      # Finish early if the lease was extended
      return cred, extended if extended

      # If the lease was expired, renew_state is :expired
      return nil, false if renew_state == :expired

      # Since the lease wasn't extended, we need to get a new lease.
      [get_credential(mount, role), false]
    end
    private :extend_or_replace_credential

    # Request a renewal of the lease of this credential.
    # If increment is not specified, we will attempt to extend the lease
    # to the base duration again.
    #
    # If increment is specified, we will attempt to set the duration to the
    # specified increment
    #
    # Increment is advisory.
    #
    # Renew returns :renewed, :expired depending on the result of the
    # renew operation. Note that the renew can succeed without actually
    # extending the duration of the credential lease.
    def renew_credential(cred, increment = nil)
      request = Net::HTTP::Put.new("/#{VAULT_VERSION}/sys/renew/#{cred.lease_id}", @header)

      request.body = JSON.generate(increment: increment) unless increment.nil?

      response_hash = JSON.parse(@vault_host.request(request).body)

      # Bail if the lease_id is nil
      return :expired if response_hash['lease_id'].nil?

      # I want the attributes on Credential to be readonly, because users of that
      # class have no reason to modify them (and doing so could break things).
      # So, I'm using instance_variable_set inside here to allow the attributes
      # to stay that way.
      cred.instance_variable_set(:@lease_duration, response_hash['lease_duration'])
      cred.instance_variable_set(:@last_renew_time, Time.now)

      :renewed
    end

    # Revoke the credential in Vault, returning the HTTP status code, 204 if everything
    # was okay.
    def revoke_credential(cred)
      request = Net::HTTP::Put.new("/#{VAULT_VERSION}/sys/revoke/#{cred.lease_id}", @header)
      @vault_host.request(request).code.to_i
    end

    # Find the backend type of mount (generic, mysql, postgresql, cassandra, aws)
    def mount_type(mount)
      mounts["#{mount}/"]['type']
    end

    # A credential is a vault secret containing minimally a data hash.
    class Credential
      # The unique id representing this credential's lease
      attr_reader :lease_id
      # The last time this id was renewed.
      attr_reader :last_renew_time
      # The length of time from that last renew that this lease will last
      attr_reader :lease_duration
      # The actual auth data of this credential (type specific)
      attr_reader :data
      # The vault backend type that this credential is from.
      attr_reader :type
      # Whether we can renew this credential
      attr_reader :renewable

      # Create a new credential of the given type given a option hash in the style of
      # the kind returned from the vault HTTP api. There's not really a reason to create
      # credentials directly, but rather using the Vagrantworld::Vault.get_credential() method.
      def initialize(type, options = {})
        @type = type
        # I think these fields always are set.
        @data = options['data']
        @lease_id = options['lease_id']
        @renewable = options['renewable']
        @lease_duration = options['lease_duration']

        # Our local state
        @last_renew_time = Time.now
      end

      # Return whether this credential is renewable
      alias renewable? renewable

      # Return the projected expiration time of this credential.
      def expiration_time
        @last_renew_time + @lease_duration
      end
    end
  end
end
