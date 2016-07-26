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

# Combine ip and vrrp interfaces and make it so that you can submit ranges
# to the interface

require File.expand_path(
    File.join(File.dirname(__FILE__),
              '..', '..', '..', 'puppet_x', 'pn', 'mixin_helper.rb'))

include PuppetX::Pluribus::MixHelper

Puppet::Type.type(:pn_vrouter_if).provide(:netvisor) do

  # no path so only one provider for Solaris and Linux
  #  both platforms have cli in /usr/bin/cli
  #
  commands :cli => 'cli'

  def self.instances
    get_ifs.collect do |interface|
      if_props = get_if_props(interface)
      new(if_props)
    end
  end

  def self.get_ifs
    cli('vrouter-interface-show', 'format',
        'ip,vlan,netmask,nic', PDQ).split("\n")
  end

  def self.get_if_props(interface)
    if_props = {}
    interface = interface.split('%')
    if_props[:ensure]        = :present
    if_props[:provider]      = :netvisor
    if_props[:name]          = interface[2] + ' ' + interface[1] + '/' +
                               interface[3]
    if_props[:vrouter]       = interface[0]
    nic = interface[4]
    using_nic = cli('vrouter-interface-show', 'vrrp-primary', nic, 'format',
                    'ip,netmask,vrrp-priority', PDQ).strip

    if using_nic != ''
      un = using_nic.split('%')
      if_props[:vrrp_ip] = un[1] + '/' + un[2]
      if_props[:vrrp_priority] = un[3]
    else
      if_props[:vrrp_ip] = if_props[:vrrp_priority] = :none
    end

    if_props
  end

  def self.prefetch(resources)
    instances.each do |provider|
      if resource = resources[provider.name]
        resource.provider = provider
      end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create

    @vrouter_name = nil
    ip = resource[:name].split(' ')[1]
    ip, mask = ip.split('/')

    locations = cli(*splat_switch, 'vrouter-show', 'format', 'location,name',
                    PDQ).split("\n")

    locations.each do |vrouter|
      loc, vrouter = vrouter.split('%')
      if loc == switch_location
        @vrouter_name = vrouter
      end
    end

    vlan = resource[:name].split(' ')[0]

    vlans = cli(*splat_switch, 'vlan-show', 'format', 'id', PDQ).split("\n")
    vlans.each do |v|
      v = v.split('%')
      vlan = nil if v[0] == vlan
    end

    if vlan
      cli(*splat_switch, 'vlan-create', 'id', vlan, 'scope', 'fabric')
    end

    vlan = resource[:name].split(' ')[1].split('.')[0]
    unless @vrouter_name
      vnet = cli(*splat_switch, 'vnet-show',
                 'format', 'name', PDQ).split("\n")[0].split('%')[0]
      location = `hostname`.strip
      @vrouter_name = "#{location.split('.')[0]}-vrouter"
      cli('vrouter-create', 'name', @vrouter_name, 'vnet', vnet, 'enable',
          'hw-vrrp-id', '18', Q)
    end

    cli(*splat_switch, 'vrouter-interface-add', 'vrouter-name', @vrouter_name,
        'ip', resource[:name].split(' ')[1], 'vlan', vlan, 'if', 'data')

    if resource[:vrrp_ip] != :none and resource[:vrrp_priority] != :none
      cli(*splat_switch, 'vrouter-interface-add', 'vrouter-name', @vrouter_name,
          'ip', resource[:vrrp_ip], 'vlan', vlan, 'vrrp-primary',
          get_nic(1, @vrouter_name, ip, mask, vlan), 'vrrp-priority',
          resource[:vrrp_priority])
    end

  end

  def destroy
    # nics to destroy
    nics = []

    vlan = resource[:name].split(' ')[0]
    ip, mask = resource[:name].split(' ')[1].split('/')

    interface_ip = build_ip(1, ip, mask, vlan)

    out = cli(*splat_switch, 'vrouter-interface-show', 'vrouter-name',
              @property_hash[:vrouter], 'ip', interface_ip, 'format', 'nic',
              PDQ).split("\n")

    out.each do |o|
      nics.push(o.split('%')[1].strip)
    end
    nics.sort.reverse.each do |n|

      cli(*splat_switch, 'vrouter-interface-remove', 'vrouter-name',
          @property_hash[:vrouter], 'nic', n)

    end
  end

  def switch
    resource[:switch]
  end

  def vrrp_ip
    if @property_hash[:vrrp] or (resource[:vrrp_ip] != :none \
                                 and resource[:vrrp_priority] != :none)

      @property_hash[:vrrp_ip]

    else
      resource[:vrrp_ip]
    end
  end

  def vrrp_ip=(value)
    destroy
    create
  end

  def vrrp_priority
    @property_hash[:vrrp_priority]
  end

  def vrrp_priority=(value)
    destroy
    create
  end

end
