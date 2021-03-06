fs   = require 'fs'
qemu = require './qemu'

Disk   = require './src/disk'
host   = require './src/host'
vmConf = require './src/vmCfg'

config       = require './config'
socketServer = require './socketServer'

isos  = []
disks = []
vms   = []


getGuestByName = (guestName) ->
  for guest in vms
    return guest if guestName is guest.name
  throw new Error "Guest: #{guestName} not Found"


module.exports.createDisk = (disk, cb) ->
  Disk.create disk, (ret) ->
    if      ret.status is 'error'
      cb {status:'error', msg:'disk not created'}

    else if ret.status is 'success'
      disks.push disk.name

      Disk.info disk.name, (ret) ->
        cb {status:'success', msg:'disk sucessfully created', data:ret}

###
#   create VM
###
module.exports.createVm = (vmCfg, cb) ->
  for vm in vms
    if vm.name is vmCfg.name
      cb status:'error', msg:"VM with the name '#{vmCfg.name}' already exists"
      return
  
  vmCfg.status = 'stopped'
  vmCfg.settings['qmpPort'] = config.getFreeQMPport()
  if vmCfg.settings.vnc
    vmCfg.settings.vnc      = config.getFreeVNCport()
  if vmCfg.settings.spice
    vmCfg.settings.spice    = config.getFreeSPICEport()

  obj = qemu.createVm vmCfg
  vms.push obj
  socketServer.toAll 'set-vm', vmCfg

  if vmCfg.settings.boot is true
    obj.start ->
      console.log "vm #{vmCfg.name} started"
      cb {status:'success', msg:'vm created and started'}
      socketServer.toAll 'set-vm-status', vmCfg.name, 'running'
      obj.setStatus 'running'

  cb {status:'success', msg:'created vm'}


module.exports.changeGuestConfEntry =(guestName, conf) ->
  try
    guest = getGuestByName guestName
    data  = conf.access.split '.'
    b     = guest.cfg
    b     = b[data.shift()] while data.length > 1
    b[data.shift()] = conf.val
    guest.saveConf()

###
  NEW ISO
###  
module.exports.newIso = (isoName) ->
  newIso = {name:isoName, size:fs.statSync("#{process.cwd()}/isos/#{isoName}").size}
  isos.push newIso
  socketServer.toAll 'set-iso', newIso

    
setInterval ->
  # @ToDo if clients connected
  for vm in vms
    if vm.cfg.status is 'running' and vm.cfg.hardware.disk isnt false
      Disk.info vm.cfg.hardware.disk, (ret) ->
        socketServer.toAll 'set-disk', ret.data
, 60 * 1000

setInterval ->
  # @ToDo if clients connected
  socketServer.toAll 'set-host', host()
, 15 * 1000
  

###

###
module.exports.qmpCommand = (qmpCmd, guestName, cb = () ->) ->
  try
    guest = getGuestByName guestName
    guest[qmpCmd](->)
  catch e
    cb {type:'error', msg:'VM not available'}


module.exports.stopQmp = (guestName) ->
  try
    guest = getGuestByName guestName
    guest.stopQMP()


###
  RETURN ISOS, DISKS, VMS
###
module.exports.getIsos  = -> return isos
module.exports.getDisks = -> return disks
module.exports.getVms   = -> return vms


###
  DELETE DISK, ISO, GUEST
###
module.exports.deleteIso = (isoName) ->
  try
    fs.unlinkSync "#{process.cwd()}/isos/#{isoName}"
    
    for iso,i in isos
      if iso.name is isoName
        isos.splice i,1
        return true
  catch e
    return false
  return false

# TODO also delete from guest
module.exports.deleteDisk = (diskName) ->
  for disk,i in disks
    if disk is diskName
      for vm in vms
        if vm.hardware.disk is diskName
          if vm.status is 'stopped'
            if Disk.delete disk
              disks.splice i, 1
              return true
  
  return false

module.exports.deleteGuest = (guestName) ->
  for guest,i in vms
    if guest.name is guestName
      vms.splice i, 1
      return true
  return false


###
  SET UP ISOS, DISKS, VM CONFIGS, exttensions
###
module.exports.loadFiles = ->
  for isoName in config.getIsoFiles()                                           # iso  files
    isos.push {name:isoName, size:fs.statSync("#{process.cwd()}/isos/#{isoName}").size}
  console.log "isos found in isos/"
  console.dir  isos
  
  disks.push diskName.split('.')[0] for diskName in config.getDiskFiles()       # disk files
  
  console.log "disks found in disks/"
  console.dir  disks    
  
  for vmCfgFile in config.getVmConfigs()                                        # vm config files
    vmCfg = vmConf.open vmCfgFile
    
    config.setToUsed 'qmp',   vmCfg.settings.qmpPort if vmCfg.settings.qmpPort
    config.setToUsed 'vnc',   vmCfg.settings.vnc     if vmCfg.settings.vnc
    config.setToUsed 'spice', vmCfg.settings.spice   if vmCfg.settings.spice
    
    vms.push qemu.createVm vmCfg
    
  console.log "vms found in vmConfigs/"
  console.log  vms.length

module.exports.reconnectVms = ->
  config.getRunningPids (pids) ->
    for pid in pids
      if guestName = config.getGuestNameByPid pid
        console.log "#{guestName} for #{pid}"
        for vm in vms
          vm.connectQmp ( ->) if vm.name is guestName

module.exports.loadExtensions = ->
  files = config.getVmHandlerExtensions()
  console.log "Found vmHandlerExtensions:"
  console.dir  files
  
  for file in files
    @setExtensionCallback file

module.exports.setExtensionCallback = (extension) ->
  module.exports[extension] = (guestName) ->
    for guest in vms
      if guest.name is guestName
        (require "#{process.cwd()}/lib/src/vmHandlerExtensions/#{extension}") guest
