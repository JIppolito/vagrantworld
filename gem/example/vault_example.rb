#!/usr/bin/ruby

require 'time'

require_relative '../lib/vagrantworld'

# This example will work if run inside the Vagrant dev environment.

vault = Vagrantworld::Vault.new('http://vault:8200', `cat /root.token`)

cred = vault.get_credential('mysql', 'readonly') do |c, renewed|
  # Update the cred object if we got a replacement instead of a renewal.
  cred = c unless renewed
  if c.nil?
    puts 'Cred was not able to be renewed or replaced, probably due to revocation or expiry.' if c.nil?
  else
    puts "Cred was renewed, and now expires at #{cred.expiration_time}"
  end
end
puts "Excellent. Our shiny credential expires at #{cred.expiration_time}"

# We can do things for a while...
sleep(70)
# We should see in the output the code block be invoked every renew.

# Be a good citizen by cleaning up after ourselves...
puts "Revoking our credential at #{Time.now}."
r = vault.revoke_credential(cred)
puts 'Revocation failed?' unless r == 204

# If we keep going without the credential, we'll see that the block gets
# called once more by the autorenew with the termination values (nil, false)
# and then stops.
sleep(20)
