async         = require 'async'
fs            = require 'fs'
{print}       = require 'util'
{spawn, exec} = require 'child_process'

build = (watch, callback) ->
  if typeof watch is 'function'
    callback = watch
    watch = false
  options = ['-c', '-o', 'lib', 'src']
  options.unshift '-w' if watch

  coffee = spawn 'node_modules/.bin/coffee', options
  coffee.stdout.on 'data', (data) -> print data.toString()
  coffee.stderr.on 'data', (data) -> print data.toString()
  coffee.on 'exit', (status) -> callback?() if status is 0

buildTemplates = (callback) ->
  eco = require 'eco'
  compile = (name) ->
    (callback) ->
      fs.readFile "src/templates/#{name}.eco", "utf8", (err, data) ->
        if err then callback err
        else 
          try
            fs.mkdirSync "lib/templates/http_server"
            fs.mkdirSync "lib/templates/installer"
          fs.writeFile "lib/templates/#{name}.js", "module.exports = #{eco.precompile(data)}", callback

  async.parallel [
    compile("http_server/application_not_found.html")
    compile("http_server/layout.html")
    compile("http_server/welcome.html")
    compile("installer/com.hackplan.power.firewall.plist")
    compile("installer/com.hackplan.power.powerd.plist")
    compile("installer/resolver")
  ], callback

task 'build', 'Compile CoffeeScript source files', ->
  build()
  buildTemplates()

task 'watch', 'Recompile CoffeeScript source files when modified', ->
  build true

task 'install', 'Install power configuration files', ->
  sh = (command, callback) ->
    exec command, (err, stdout, stderr) ->
      if err
        console.error stderr
        callback err
      else
        callback()

  createHostsDirectory = (callback) ->
    sh 'mkdir -p "$HOME/Library/Application Support/Power/Hosts"', (err) ->
      fs.stat "#{process.env['HOME']}/.power", (err) ->
        if err then sh 'ln -s "$HOME/Library/Application Support/Power/Hosts" "$HOME/.power"', callback
        else callback()

  installLocal = (callback) ->
    console.error "*** Installing local configuration files..."
    sh "./bin/power --install-local", callback

  installSystem = (callback) ->
    exec "./bin/power --install-system --dry-run", (needsRoot) ->
      if needsRoot
        console.error "*** Installing system configuration files as root..."
        sh "sudo ./bin/power --install-system", (err) ->
          if err
            callback err
          else
            sh "sudo launchctl load /Library/LaunchDaemons/com.hackplan.power.firewall.plist", callback
      else
        callback()

  async.parallel [createHostsDirectory, installLocal, installSystem], (err) ->
    throw err if err
    console.error "*** Installed"

task 'start', 'Start power server', ->
  agent = "#{process.env['HOME']}/Library/LaunchAgents/com.hackplan.power.powerd.plist"
  console.error "*** Starting the Power server..."
  exec "launchctl load '#{agent}'", (err, stdout, stderr) ->
    console.error stderr if err

task 'stop', 'Stop power server', ->
  agent = "#{process.env['HOME']}/Library/LaunchAgents/com.hackplan.power.powerd.plist"
  console.error "*** Stopping the Power server..."
  exec "launchctl unload '#{agent}'", (err, stdout, stderr) ->
    console.error stderr if err
