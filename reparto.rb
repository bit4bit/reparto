#Reparto 0.0
#::Author:: bit4bit <bit4bit@riseup.net>
#::Date:: 15 abril 2012 




require 'find'

begin
  require 'inifile'
  require 'r18n-desktop'
  require 'logger'
  require 'net/ssh'
  require 'net/sftp'

rescue LoadError
  require 'rubygems'
  require 'net/ssh'
  require 'net/sftp'
  require 'inifile'
  require 'r18n-desktop'
  require 'logger'
end

REPARTO_VERSION = 0.0
$t = R18n.from_env 'i18n/','es'
$logs = Logger.new(STDOUT)
$threads = []

class String
  def is_number?
    true if Float(self) rescue false
  end
end

class SSHClient
  def initialize(ip, port, username, password)
    @ip = ip
    @port = port
    @username = username
    @password = password

    @actions = []
  end

  #ejecuta acciones
  def do
    $logs.debug($t.reparto.conecting(@ip))

    Net::SSH.start(@ip, @username, :password => @password) do |ssh|
      @actions.each do |action|
        name = action[:action]


        case name
        when :cmd
          cmd = action[:cmd]
          $logs.debug("%s command execute: %s" % [@ip,cmd])
          r = ssh.exec! cmd
          $logs.debug("%s command return: %s" % [@ip,r])
        when :cp
          local = action[:local]
          remote = action[:remote]
          
          unless File.exist? local
            $logs.error("%s Not found %s to copy on local machine" % [@ip,local])
            next
          end

          begin
            ssh.sftp.connect do |sftp|

              begin
                remote = File.join(remote, File.basename(local)) if ssh.sftp.file.directory? remote
              rescue
              end

              sftp.upload!(local, remote)
              $logs.debug("%s cp: %s %s" % [@ip, local, remote])

            end
          rescue Net::SFTP::StatusException => e
            $logs.error("%s error[%s] cp: %s %s" % [@ip, e.description, local, remote])
          end

          #Copia directorio local con remoto solo si no existe
        when :cpdir
          local = action[:local]
          remote = action[:remote]

          unless File.directory? local
            $logs.error("%s Only dir allow for cpdir not %s" % [@ip, local])
          end

          begin
            ssh.sftp.upload!(local, remote)
            $logs.debug("%s cpdir: %s %s" % [@ip, local, remote])

          rescue Net::SFTP::StatusException => e
            case e.code
            when 4
              $logs.error("%s error[Can't copy directory already exist, use updatedir] cpdir: %s %s" % [@ip, local, remote])
            else
              $logs.error("%s error[%s] cpdir: %s %s" % [@ip, e.description, local, remote])
            end
          rescue ArgumentError
            $logs.error("%s error[Need directory to upload] cpdir: %s %s" % [@ip, local, remote])
          end

          #Actualiza directory local con remoto
        when :updatedir

          ssh.sftp.connect do |sftp|
            local_dir = action[:local]
            remote_dir = action[:remote]

            $logs.debug("Checking for files which need updating %s" % @ip)
            Find.find(local_dir) do |file|
              local_file = file
              remote_file = File.join(remote_dir, local_file.sub(local_dir, ''))

              #actualiza directorio no existene en el remoto
              if File.directory? file
                begin
                  ssh.sftp.file.directory? remote_file
                rescue Net::SFTP::StatusException => e
                  if e.code == 2
                    sftp.upload!(file, remote_file)
                    $logs.debug("%s Updating, new dir %s" % [@ip, remote_file])
                  else
                    $logs.error("%s error[%s] updating new dir %s" % [@ip, e.description, remote_file])
                  end
                end
                next
              end
              
              #actualiza comparando mtime de stat
              #o fechas de modificacion
              begin
                lstat = File.stat(local_file)
                rstat = sftp.stat!(remote_file)

                if lstat.mtime > Time.at(rstat.mtime)
                  $logs.debug("%s Updating %s" % [@ip, remote_file])
                  sftp.upload!(local_file, remote_file)
                  sftp.setstat!(remote_file, :permissions => lstat.mode)
                end
              rescue Net::SFTP::StatusException => e
                if e.code == 2
                  sftp.upload!(local_file, remote_file)
                  $logs.debug("%s Updating new file %s" % [@ip, remote_file])
                else
                  $logs.error("%s error[%s] updating new file %s" % [@ip, e.description, local_file])
                end
              rescue Errno::ENOENT
                $logs.error("%s error[No such directory] updating: %s %s" % [@ip, local_file, remote_file])
              end
            end
          end
        end
      end
    end
  end
  
  def <<(action)
    @actions << action
  end

  #Ejecuta comando en cliente
  #::cmd:: comando en cliente
  def cmd(cmd)
    @actions << {:action => :cmd, :cmd => cmd}
  end

  #Copia archivo local a remote
  #::local:: archivo local
  #::remote:: archivo remote
  def cp(local, remote)
    @actions << {:action => :cp, :local =>local, :remote =>remote}
  end

  #Copia directoria local a remote
  #::local:: directorio local
  #::remote:: directorio remote
  def cp_dir(local, remote)
    @actions << {:action => :cpdir, :local => local, :remote => remote}
  end

  #Actualiza directorio remote en caso de cambio
  #::dir:: directorio local/remote
  def update_dir(local, remote)
    @actions << {:action => :updatedir, :local => local, :remote => remote}
  end
end


#Clase Reparto
#Lee archivo .ini parsea, y crea hilos de ejecucion segun
#instrucciones indicadas
class Reparto
  
  #::filename:: archivo .ini
  def initialize(filename)
    @fn = filename
    @ini = IniFile.new(@fn)
    
    @ssh_clients = {}
    
    @types_supported = ['ssh']
    parse
  end
  
  #Parse el archivo indicado y crea hilos de ejecucion
  def parse

    #Por cada seccion o equipo, es un hilo
    @ini.each_section do |section|
      
      #@todo validate ip
      ip = section
      
      #obtiene tipo
      if @ini[section].has_key? $t.ini['type']
        type = @ini[section][$t.ini['type']]
        unless @types_supported.member? type
          raise RuntimeError, $t.reparto.type_not_supported(type)
        end
      else
        type = 'ssh'
      end
      
      #valida campos requeridos
      raise RuntimeError, $t.reparto.require_username unless @ini[section].has_key? $t.ini.username
      raise RuntimeError, $t.reparto.require_password unless @ini[section].has_key? $t.ini.password
      
      username = @ini[section][$t.ini.username]
      password = @ini[section][$t.ini.password]
      
      #se obtiene puerto o por defecto 22
      if @ini[section].has_key? $t.ini.port
        port = @ini[section][$t.ini.port]
        unless port.is_number?
          raise RuntimeError, $t.reparto.port_numeric
        end
        port = port.to_i
      else
        case type
        when 'ssh'
          port = 22
        end
      end

      #comandos a ejecutar
      #en orden , segun paramentro terminado en [0-9]+
      cmds = []
      cmd_index = nil

      #se lee parametros y se asignan segun nombre
      @ini[section].keys.each do |param|
        cpdirs = nil
        cpfiles = nil
        updatedirs = nil

        cmd = param.match(/cmd_([0-9]+)/)
        if param =~ /cmd/
          cmd_index = cmd[1].to_i
          cmds[cmd_index] = ["cmd",  @ini[section][param]]
        end

        #cp directorios
        cpdir = param.match(/cpdir_local_([0-9]+)/)
        if cpdir
          cpdir_num = cpdir[1].to_i
          cpdir_index = "cpdir_%d" % cpdir_num
          cmd_index = cpdir_num
          cpdirs = cmds.assoc(cpdir_index)

          if cpdirs.nil?
            cpdirs = [cpdir_index, {}] 
            cpdirs[1][:local] = @ini[section][param]            
            cmds[cmd_index] = cpdirs
          else
            cmds[cmds.index{|x| x[0] == cpdir_index unless x.nil?}][1][:local] = @ini[section][param]
          end
        end

        cpdir = param.match(/cpdir_remote_([0-9]+)/)
        if cpdir
          cpdir_num = cpdir[1].to_i
          cpdir_index = "cpdir_%d" % cpdir_num
          cmd_index = cpdir_num
          cpdirs = cmds.assoc(cpdir_index) 
          if cpdirs.nil?
            cpdirs = [cpdir_index, {}]
            cpdirs[1][:remote] = @ini[section][param]
            cmds[cmd_index] = cpdirs
          else
            cmds[cmds.index{|x| x[0] == cpdir_index unless x.nil?}][1][:remote] = @ini[section][param]
          end
        end
        

        #cp archivos
        cpfile = param.match(/cp_local_([0-9]+)/)
        if cpfile
          cp_num = cpfile[1].to_i
          cp_index = "cp_%d" % cp_num
          cmd_index = cp_num
          cpfiles = cmds.assoc(cp_index)
          if cpfiles.nil?
            cpfiles = [cp_index, {}]
            cpfiles[1][:local] = @ini[section][param]
            cmds[cmd_index] = cpfiles
          else
            cmds[cmds.index{|x| x[0] == cp_index unless x.nil?}][1][:remote] = @ini[section][param]
          end
        end
        
        cpfile = param.match(/cp_remote_([0-9]+)/)
        if cpfile
          cp_num = cpfile[1].to_i
          cp_index = "cp_%d" % cp_num
          cmd_index = cp_num
          cpfiles = cmds.assoc(cp_index)
          if cpfiles.nil?
            cpfiles = [cp_index, {}]
            cpfiles[1][:remote] = @ini[section][param]
            cmds[cmd_index] = cpfiles
          else
            cmds[cmds.index{|x| x[0] == cp_index unless x.nil?}][1][:remote] = @ini[section][param]
          end
        end


        #actualiza archivos/directorios en remoto
        updatedir = param.match(/updatedir_([a-z]+_)?([0-9]+)/)

        if param =~ /^updatedir_([0-9]+)$/
          i_num = updatedir[2].to_i
          cmd_index = i_num
          up_index = "updatedir_%d" % i_num
          updatedirs = cmds.assoc(up_index)
          if updatedirs.nil?
            updatedirs = [up_index, {}]
            updatedirs[1][:remote] = @ini[section][param]
            updatedirs[1][:local] = @ini[section][param]
            cmds[cmd_index] = updatedirs
          else
            cmds[cmds.index{|x| x[0] == up_index unless x.nil?}][1][:local] = @ini[section][param]
            cmds[cmds.index{|x| x[0] == up_index unless x.nil?}][1][:remote] = @ini[section][param]
          end
        end

        if param =~ /^updatedir_local/
          i_num = updatedir[2].to_i
          cmd_index = i_num
          up_index = "updatedir_%d" % i_num
          updatedirs = cmds.assoc(up_index)
          if updatedirs.nil?
            updatedirs = [up_index, {}] 
            updatedirs[1][:local] = @ini[section][param]
            cmds[cmd_index] = updatedirs
          else
            cmds[cmds.index{|x| x[0] == up_index unless x.nil?}][1][:local] = @ini[section][param]
          end
        end

        if param =~ /^updatedir_remote/
          i_num = updatedir[2].to_i
          cmd_index = i_num
          up_index = "updatedir_%d" % i_num
          updatedirs = cmds.assoc(up_index)
          if updatedirs.nil?
            updatedirs = [up_index, {}] 
            updatedirs[1][:remote] = @ini[section][param]
            cmds[cmd_index] = updatedirs
          else
            cmds[cmds.index{|x| x[0] == up_index unless x.nil?}][1][:remote] = @ini[section][param]
          end
        end


      end

      case type
      when 'ssh'
        cssh = SSHClient.new(ip, port, username, password)
        cmds.each do |cmd|
          next if cmd.nil?
          type = cmd[0]
          args = cmd[1]

          if type =~ /cmd/
            cssh.cmd(args)
          elsif type =~ /cpdir/
            cssh.cp_dir(args[:local], args[:remote])
          elsif type =~ /cp/
            cssh.cp(args[:local], args[:remote])
          elsif type =~ /updatedir/
            cssh.update_dir(args[:local], args[:remote])
          else
            $logs.error("Unknown action %s\n" % type)
          end
        end

        #Hilo por cliente
        $threads << Thread.new(cssh) do |tssh|
          begin
            cssh.do
          rescue Errno::ENETUNREACH
            $logs.error("Can't connect to %s" % ip)
          rescue Errno::EHOSTUNREACH
            $logs.error("Can't route to host %s" % ip)
          end
        end
        
      end
      
    end
  
  end
  
end


#Muestra ayuda de uso
def usage
  print $t.reparto.usage($0, REPARTO_VERSION)
  exit -1
end

if $0 == __FILE__
  usage if ARGV.size != 1 or not File.exist? ARGV[0]
  r = Reparto.new(ARGV[0])
  $threads.each do |th|
    th.join
  end
end
