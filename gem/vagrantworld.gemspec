Gem::Specification.new do |s|
  s.name = 'vagrantworld'
  s.version = '0.0.1'
  s.summary = 'Vagrantworld DevOps support code'
  s.description = <<-DESC
    The Vagrantworld gem provides support for DevOps related services in ruby,
    including Zookeeper, Consul and Vault credential management. Extends Ruby Diplomat (Consul), 
    Zookeeper gem, vault-ruby for Vault
  DESC
  s.author = 'Jeff Ippolito'
  s.files = ['lib/vagrantworld.rb', 'lib/vagrantworld/consul.rb', 'lib/vagrantworld/vault.rb']

  s.add_development_dependency 'simplecov', ['= 0.11.2']
end
