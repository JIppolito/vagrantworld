require 'net/http'
require 'json'

module Vagrantworld
  # API Version of consul. This is prepended to the route.
  CONSUL_VERSION = 'v1'.freeze

  # Consul provides a wrapper around the Hashicorp Consul API
  class Consul
    # Create a new Consul client
    def initialize(address)
      uri = URI(address)
      @consul_host = Net::HTTP.new(uri.host, uri.port)
    end

    # Retrieve a hash of the services registered in the Consul catalog.
    def services
      get('catalog/services')
    end

    # Retrieve a hash of the nodes registered in the Node catalog
    def nodes
      get('catalog/nodes')
    end

    # Retrieve information on a service with the given name.
    # Returns an array of nodes.
    def service(name)
      get("catalog/service/#{name}")
    end

    # Retrieve information on a node with the given name.
    # Returns a (Node, Services[]) hash.
    def node(name)
      get("catalog/node/#{name}")
    end

    # This is a private helper function for making requests to the consul endpoint.
    # This method returns a hash conversion of the json response.
    def get(path)
      JSON.parse(@consul_host.get("/#{CONSUL_VERSION}/#{path}").body)
    end
    private :get

    # simple_register will register (to the catalog) a new node and service with
    # the given name, located at the given ip, and on the given port.
    #
    # This method is most suitable when each service has its own box (or at least
    # hostname), has only one port associated with it, and is not on a box with
    # a Consul Agent.
    def simple_register(name, ip, port)
      @consul_host.put('/v1/catalog/register', JSON.generate(
        Node: name,
        Address: ip,
        Service: {
          ID: name,
          Service: name,
          Address: ip,
          Port: port
        }
      ))
    end

    def simple_deregister(name)
      @consul_host.put('/v1/catalog/deregister', JSON.generate(
        Node: name
      ))
    end
  end
end
