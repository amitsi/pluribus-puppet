# Copyright 2016 Pluribus Networks
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

Puppet::Type.type(:pn_cluster).provide(:netvisor) do

  desc "Provide Netvisor support for clustering management."

  commands :cli => 'cli'

  # Helper method to check that the specified nodes exist and are present on the
  # connected fabric.
  # Fails if the nodes aren't actually connected or don't exist.
  # @return: true, this method will return true or cause a failure
  #
  def check_nodes
    fabric_nodes = cli('--quiet', 'fabric-node-show', 'format', 'name,',
                       'no-show-headers').split("\n")
    fabric_nodes.each do |node|
      node.strip!
    end
    resource[:nodes].each do |node|
      cli('--quiet', 'switch', node) =~ /switch:/ and
          fail("Cannot find node #{node}")
      fabric_nodes.include? node or fail("Cannot find node #{node} on the " +
                                             "current fabric")
    end
  end

  # Helper method to get the names of the switches connected to a specific
  # cluster.
  # @param cluster_name: The name of the cluster.
  # @return: an array containing the two nodes in the current cluster.
  #
  def get_clustered_nodes(cluster_name)
    cluster_name.strip!
    cluster_nodes = []
    nodes_list = cli('--quiet', 'cluster-show', 'name', cluster_name, 'format',
        'cluster-node-1,cluster-node-2', 'no-show-headers',
        'parsable-delim', '%').split('%')
    nodes_list.each do |name|
      name.strip!
      cluster_nodes.push(name)
    end
  end

  def exists?
    check_nodes
    current_names = cli('--quiet', 'cluster-show', 'format', 'name',
                        'no-show-headers').split ("\n")
    current_names.each do |name|
      name.strip!
      if name == resource[:name]
        current_nodes = get_clustered_nodes(name)
        if (current_nodes[0] == resource[:nodes][0] and
            current_nodes[1] == resource[:nodes][1]) or
            (current_nodes[1] == resource[:nodes][0] and
            current_nodes[0] == resource[:nodes][1])
          return true
        elsif (current_nodes[0] != resource[:nodes][0] or
            current_nodes[1] != resource[:nodes][1]) or
            (current_nodes[1] != resource[:nodes][0] or
                current_nodes[0] != resource[:nodes][1])
          if resource[:force_clustering] == :yes
            fail("Forcing clustering is currently unsuppoted")
          else
            nodes = get_clustered_nodes(name)
            if nodes.include? resource[:nodes][0] and
                not nodes.include? resource[:nodes][1]
              fail("Node #{resource[:nodes][0]} is already a member of a " +
                       "cluster!")
            elsif nodes.include? resource[:nodes][1] and
              not nodes.include? resource[:nodes][0]
              fail("Node #{resource[:nodes][1]} is already a member of a " +
                       "cluster!")
            else
              fail("Nodes #{resource[:nodes][0]} and #{resource[:nodes][1]} " +
                       "are members of clusters!")
            end
          end
        end
      else
        current_nodes = get_clustered_nodes(name)
        if (current_nodes[0] == resource[:nodes][0] and
            current_nodes[1] == resource[:nodes][1]) or
            (current_nodes[1] == resource[:nodes][0] and
                current_nodes[0] == resource[:nodes][1])
          # Cluster is established but name is different than specified
          cli('cluster-delete', 'name', name)
          if resource[:ensure].to_s == 'present'
            create
            return true
          else
            return false
          end
        else # TODO Nodes are in a different cluster
          # Has a different name and different nodes; do nothing
        end
      end
    end
    return false
  end

  def name
    # Always true, leave all error handling to exists?
    resource[:name]
  end

  def create
    cli('cluster-create', 'name', resource[:name], 'cluster-node-1',
        resource[:nodes][0], 'cluster-node-2', resource[:nodes][1])
  end

  def destroy(name = resource[:name])
    clusters = cli('--quiet', 'vlag-show', 'format', 'cluster',
                   'no-show-headers').split("\n")
    clusters.each do |c|
      c.strip!
      if c == resource[:name]
        # Destroy the VLAG before the cluster
        vlag_name = cli('--quiet', 'vlag-show', 'cluster', c, 'format', 'name',
                        'no-show-headers').strip
        vlag_name.chomp.strip!
        cli('--quiet', 'vlag-delete', 'name', vlag_name)
      end
    end
    cli('cluster-delete', 'name', name)
  end

  def nodes
    # Always return true, handled in exists?
    resource[:nodes]
  end

  def force_clustering
    # Always return true, not a verifiable attribute.
    resource[:force_clustering]
  end

end
