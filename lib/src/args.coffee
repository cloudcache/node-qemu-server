os     = require 'os'
crypto = require 'crypto'

class Args
  constructor: ->
    @args    = [ 'qemu-system-x86_64', '-nographic', '-parallel', 'none', '-serial', 'none']
    @qmpPort = 0
    @macAddr = crypto.randomBytes(6).toString('hex').match(/.{2}/g).join ':'
  
  ###
  #   QEMU START OPTIONS  
  ###      
  pushArg: ->
    @args.push arg for arg in arguments
  
  ###
  #   no defaults, no default config
  ###
  nodefconfig: ->
    @pushArg '-nodefconfig'
    return this
  
  nodefaults: ->
    @pushArg '-nodefaults'
    return this
  
  ###
  #   set harddrive, set cdromdrive
  ###  
  hd: (img, intf='ide') ->
    @pushArg '-drive', "file=disks/#{img}.img,media=disk,if=#{intf}"
    return this
  partition: (partition, intf='ide') ->
    @pushArg '-drive', "file=#{partition},media=disk,if=#{intf},cache=none"
    return this
  cd: (img, intf='ide') ->
    @pushArg '-drive', "file=isos/#{img},media=cdrom,if=#{intf}"
    return this
  
  snapshot: () ->
    @pushArg '-snapshot'
    return this
  
  boot: (type, once = true) ->
    args = ''
    if once is true
      args += 'once='
    
    if      type is 'hd'
      args = "#{args}c"
    else if type is 'cd'
      args = "#{args}d"
    else if type is 'net'
      args = "#{args}n"
    
    @pushArg '-boot', args
    return this
  
  ram: (ram) ->
    @pushArg '-m', "#{ram}M"
    return this
  
  # CPU // -smp [cpus=]n[,cores=cores][,threads=threads][,sockets=sockets][,maxcpus=maxcpus]
  cpus: (cores=1, threads=1, sockets=1) ->
    @pushArg '-smp', "cpus=#{threads*sockets},cores=#{cores},threads=#{threads},sockets=#{sockets}"
    return this
  
  # // -cpu model
  cpuModel: (model) ->
    @pushArg '-cpu', model
    return this
  
  # NUMA // numactl --cpunodebind={} --membind={}
  hostNuma: (cpuNode, memNode) ->
    @args.unshift '--'
    @args.unshift "--membind=#{memNode}"
    @args.unshift "--cpunodebind=#{cpuNode}"
    @args.unshift 'numactl'
    return this
  # NUMA
  
  machine: (machine) ->
    @pushArg '-machine', "type=#{machine}"
    return this
  
  accel: (accels) ->
    @pushArg '-machine', "accel=#{accels}"
    return this
  
  kvm: ->
    @pushArg '-enable-kvm'
    return this
  
  usbOn: (usbVersion = 2) ->
    if      2 is Number usbVersion
      @pushArg '-device', 'usb-ehci,id=usb,bus=pci.0,addr=0x4' # pass usb 2.0
    else if 3 is Number usbVersion
      @pushArg '-device', 'nec-usb-xhci,id=usb,bus=pci.0,addr=0x4' #p pass usb 3.0
    return this
  
  usbDevice: (vendorId, productId) ->
    @pushArg '-device', "usb-host,vendorid=0x#{vendorId},productid=0x#{productId},id=hostdev0,bus=usb.0"
    return this
  
  vnc: (port) ->
    @pushArg '-vnc', ":#{port}"
    return this
  
  spice: (port, addr, password = false) ->
    if password is false
      @pushArg '-spice', "port=#{port},addr=#{addr},disable-ticketing"
    else
      @pushArg '-spice', "port=#{port},addr=#{addr},password='#{password}'"
    return this  
  
  mac: (addr) ->
    @macAddr = addr
    return this
  
  net: (macAddr, card = 'rtl8139', mode = 'host', opts)->
    @mac macAddr
    
    if      mode is 'host' or os.type().toLowerCase() is 'darwin'
      ext = 'user'
      if opts?
        ext += ",dhcpstart=#{opts.guestIp}"
        ext += ",hostfwd=tcp:#{fwd.hostIp}:#{fwd.hostPort}-#{opts.guestIp}:#{fwd.guestPort}" for fwd in opts.fwds
        
      @pushArg '-net', "nic,model=#{card},macaddr=#{macAddr}", '-net', ext
    else if mode is 'bridge'
      @pushArg '-net', "nic,model=#{card},macaddr=#{macAddr}", '-net', 'tap'
    
    return this
  
  vga: (vga = 'none') ->
    @pushArg '-vga', vga
    return this
  
  qmp: (port) ->
    @qmpPort = port
    @pushArg '-qmp', "tcp:127.0.0.1:#{port},server"
    return this
  
  keyboard: (keyboard) ->
    @pushArg '-k', keyboard
    return this
  
  daemon: ->
    @pushArg '-daemonize'
    return this
  
  balloon: ->
    @pushArg '-balloon', 'virtio'
    return this
    
  noStart: ->
    @pushArg '-S'
    return this
  
  noShutdown: ->
    @pushArg '-no-shutdown'
    return this
  
module.exports.Args = Args

# qemu-system-x86_64 -smp 2 -m 1024 -nographic -qmp tcp:127.0.0.1:15004,server -k de -machine accel=kvm -drive file=/...,media=cdrom -vnc :4 -net nic,model=virtio,macaddr=... -net tap -boot once=d -drive file=/dev/...,cache=none,if=virtio
