#!/usr/bin/env bash

# Copyright 2013 BrewPi
# This file was originally part of BrewPi, and is now part of BrewPi/Fermentrack

# BrewPi is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# BrewPi is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with BrewPi.  If not, see <http://www.gnu.org/licenses/>.

# Fermentrack is free software, and is distributed under the terms of the MIT license.
# A copy of the MIT license should be included with Fermentrack. If not, a copy can be
# reviewed at <https://opensource.org/licenses/MIT>

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


########################
### This script assumes a clean Raspbian install.
### Freeder, v1.0, Aug 2013
### Elco, Oct 2013
### Using a custom 'die' function shamelessly stolen from http://mywiki.wooledge.org/BashFAQ/101
### Using ideas even more shamelessly stolen from Elco and mdma. Thanks guys!
########################


# For fermentrack, the process will work like this:
# 1. Install the system-wide packages (nginx, etc.)
# 2. Confirm the install settings
# 3. Add the users
# 4. Clone the fermentrack repo
# 5. Set up  virtualenv
# 6. Run the fermentrack upgrade script
# 7. Copy the nginx configuration file & restart nginx


package_name="Fermentrack"
github_repo="https://github.com/javogiraldez/fermentrack.git"
github_branch="master"
green=$(tput setaf 76)
red=$(tput setaf 1)
tan=$(tput setaf 3)
reset=$(tput sgr0)
myPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"

############## Command Line Options Parser

INTERACTIVE=1

# Help text
function usage() {
    echo "Usage: $0 [-h] [-n] [-r <repo_url>] [-b <branch>]" 1>&2
    echo "Options:"
    echo "  -h               This help"
    echo "  -n               Run non interactive installation"
    echo "  -r <repo_url>    Specify fermentrack repository (only for development)"
    echo "  -b <branch>      Branch used (only for development or testing)"
    exit 1
}

while getopts "nhr:b:" opt; do
  case ${opt} in
    n)
      INTERACTIVE=0  # Silent/Non-interactive Mode
      ;;
    r)
      github_repo=$OPTARG
      ;;
    b)
      github_branch=$OPTARG
      ;;
    h)
      usage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))




printinfo() {
  printf "::: ${green}%s${reset}\n" "$@"
}


printwarn() {
 printf "${tan}*** WARNING: %s${reset}\n" "$@"
}


printerror() {
 printf "${red}*** ERROR: %s${reset}\n" "$@"
}


# Functions
warn() {
  local fmt="$1"
  command shift 2>/dev/null
  echo "${red}*** ----------------------------------${reset}"
  echo "${red}*** ERROR ERROR ERROR ERROR ERROR ***${reset}"
  echo -e "${red}$fmt\n" "${@}${reset}"
  echo "${red}*** ----------------------------------${reset}"
  echo "${red}*** Mira las lineas superiores para sabes del error${reset}"
  echo "${red}*** Configuración NO completada${reset}"
  echo "${red}*** Más info en el archivo \"install.log\"${reset}"
}


die () {
  local st="$?"
  warn "$@"
  exit "$st"
}

welcomeMessage() {
  echo -n "${tan}"
  cat << "EOF"
 _____                              _                  _    
|  ___|__ _ __ _ __ ___   ___ _ __ | |_ _ __ __ _  ___| | __
| |_ / _ \ '__| '_ ` _ \ / _ \ '_ \| __| '__/ _` |/ __| |/ /
|  _|  __/ |  | | | | | |  __/ | | | |_| | | (_| | (__|   < 
|_|  \___|_|  |_| |_| |_|\___|_| |_|\__|_|  \__,_|\___|_|\_\

EOF
  echo -n "${reset}"
  echo "Bienvenido a la intalación de Fermentrack. Este script instalará Fermentrack."
  echo "Se creará un nuevo usuario y Fermentrack se instalará en su directorio home."
  echo "Cuando la instalacón finalice sin errores Fermentrack se ejecuta y monitoriza automáticamente."
  echo ""
  echo "Por favor tome nota - Cualquier app existente que requiera Apache (incluyendo RaspberryPints y BrewPi-www)"
  echo "se desactivará. Si quieres soporte para esas apps puede ser instalada opcionalmente más tarde."
  echo "Por favor lee http://apache.fermentrack.com/ para más información."
  echo ""
  echo "Para más información sobre Fermentrack, por favor visita: http://fermentrack.com/"
  echo
  if [[ ${INTERACTIVE} -eq 1 ]]; then  # Don't ask this if we're running in noninteractive mode
      read -p "¿Quieres continuar con la instalación de Fermentrack? [y/N] " yn
      case "$yn" in
        y | Y | yes | YES| Yes ) printinfo "¡Ok, allá vamos!";;
        * ) exit;;
      esac
  fi
}


verifyRunAsRoot() {
    # verifyRunAsRoot does two things - First, it checks if the script was run by a root user. Assuming it wasn't,
    # then it attempts to relaunch itself as root.
    if [[ ${EUID} -eq 0 ]]; then
        printinfo "Este script se ejecuta como root. Continuando con la instalación."
    else
        printinfo "Este script se ejecutó sin privilegios root. Instala y actualiza varios paquetes, crea una"
        printinfo "cuenta de usuario y actualiza opciones del sistema. Para countinuar este script ahora comenzará"
        printinfo "a usar 'sudo' para ejecutarse nuevamente como root. Por favor comprueba el script por cualquier"
        printinfo "error con este requerimiento. Esegúrese de acceder a este script de una fuente fiable."
        echo

        if command -v sudo &> /dev/null; then
            # TODO - Make this require user confirmation before continuing
            printinfo "El script está listo para ejecutarse nuevamente usando sudo."
            exec sudo bash "$0" "$@"
            exit $?
        else
            printerror "La utilidad sudo no parece estar disponible en este sistema, y la instalación no puede continuar."
            printerror "Por favor ejecuta este script como root y se instlará automáticamente."
            exit 1
        fi
    fi
    echo

}


# Check for network connection
verifyInternetConnection() {
  printinfo "Chequeando la conexión a Internet: "
  ping -c 3 github.com &>> install.log
  if [ $? -ne 0 ]; then
      echo
      printerror "No hay conexión a github.com. ¿Estás seguro de tener conexión a Internet?"
      printerror "La instalación se cancelará porque necesita copiar código de github.com"
      exit 1
  fi
  printinfo "¡Conexión a Internet, CORRECTA!"
  echo
}


# Check if installer is up-to-date
verifyInstallerVersion() {
  printinfo "Chequeando que este script esté actualizado..."
  unset CDPATH
  myPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"
  printinfo ""$myPath"/update-tools-repo.sh start."
  bash "$myPath"/update-tools-repo.sh &>> install.log
  printinfo ""$myPath"/update-tools-repo.sh end."
  if [ $? -ne 0 ]; then
    printerror "El script era de una versión anterior pero ya está actualizado. Ejecuta nuevamente install.sh."
    exit 1
  fi
  echo
}


# getAptPackages runs apt-get update, and installs the basic packages we need to continue the Fermentrack install
getAptPackages() {
    printinfo "Instalando dependecias utilizando apt-get"
    lastUpdate=$(stat -c %Y /var/lib/apt/lists)
    nowTime=$(date +%s)
    if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
        printinfo "La ultima vez que se ejecutó 'apt-get update' fue hace tiempo. Actualizando ahora. (Puede tomar un minuto)"
        apt-key update &>> install.log||die
        printinfo "'apt-key update' ejecutado correctamente."
        apt-get update &>> install.log||die
        printinfo "'apt-get update' ejecutado correctamente."
    fi
    # Installing the nginx stack along with everything we need for circus, etc.
    printinfo "apt está actualizado - instalando git-core, nginx, python-dev, y otros paqutes."
    printinfo "Esto puede tomar unos minutos y no se verá nada nuevo en la pantalla hasta su finalización..."

    # For the curious:
    # git-core enables us to get the code from git (har har)
    # build-essential allows for building certain python (& other) packages
    # python-dev, python-pip, and python-virtualenv all enable us to run Python scripts
    # python-zmq is used in part by Circus
    # nginx is a webserver
    # redis-server is a key/value store used for gravity sensor & task queue support
    # avrdude is used to flash Arduino-based devices

    apt-get install -y git-core build-essential python-dev python-virtualenv python-pip python-zmq nginx redis-server avrdude &>> install.log || die

    # bluez and python-bluez are for bluetooth support (for Tilt)
    # libcap2-bin is additionally for bluetooth support (for Tilt)
    # python-scipy and python-numpy are for Tilt configuration support

    apt-get install -y bluez python-bluez python-scipy python-numpy libcap2-bin &>> install.log || die

    printinfo "Todos los paquetes se han instalado correctamente."
    echo
}


verifyFreeDiskSpace() {
  printinfo "Verificando espacio disponible en el disco..."
  local required_free_kilobytes=512000
  local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # - Unknown free disk space , not a integer
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    printerror "Espacio libre en el disco, DESCONOCIDO!"
    printerror "No somos capaces de determinar el espacio libre disponible en el sistema."
    exit 1
  # - Insufficient free disk space
  elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
    printerror "Espacio en el disco, INSUFICIENTE!"
    printerror "Tu sistema aparentemente tiene poco espacio. ${package_name} recomienda un mínimo de $required_free_kilobytes KB."
    printerror "Sólo tienes ${existing_free_kilobytes} KB libres."
    printerror "Si es una instalación limpia, debería expandir tu disco."
    printerror "Prueba usando 'sudo raspi-config', y seleccioando 'expand file system option'"
    printerror "Despues de reiniciar, ejecuta la instalación otra vez."
    printerror "Espacio libre en el disco, insuficiente, Saliendo..."
    exit 1
  fi
  echo
}


verifyInstallPath() {
  if [[ ${INTERACTIVE} -eq 1 ]]; then  # Don't ask if we're in non-interactive mode
      if [ -d "$installPath" ]; then
        if [ "$(ls -A ${installPath})" ]; then
          read -p "El directorio donde se instalrá no está vacio, ¿estás seguro de utilizar esta ruta? [y/N] " yn
          case "$yn" in
              y | Y | yes | YES| Yes ) printinfo "¡Ok, te lo hemos advertido!";;
              * ) exit;;
          esac
        fi
      fi
      echo
  fi
}


createConfigureUser() {
  ### Create/configure user accounts
  printinfo "Creando y configurando la cuenta de usuario."

  if id -u ${fermentrackUser} >/dev/null 2>&1; then
    printinfo "El usuario '${fermentrackUser}' ya existe, saltando paso..."
  else
    useradd -m -G dialout ${fermentrackUser} -s /bin/bash &>> install.log ||die
    # Disable direct login for this user to prevent hijacking if password isn't changed
    passwd -d ${fermentrackUser}||die
  fi
  # add pi user to fermentrack and www-data group
  if id -u pi >/dev/null 2>&1; then
    usermod -a -G www-data ${fermentrackUser}||die
  fi
  echo
}


backupOldInstallation() {
  printinfo "Chequeando el directorio de instalación"
  dirName=$(date +%F-%k:%M:%S)
  if [ "$(ls -A ${installPath})" ]; then
    printinfo "El directorio de la instalación del script NO está vacio, haciendo un backup en la home del usuario y borrando contenidos..."
      if [ ! -d ~/fermentrack-backup ]; then
        mkdir -p ~/fermentrack-backup
      fi
      mkdir -p ~/fermentrack-backup/"$dirName"
      cp -R "$installPath" ~/fermentrack-backup/"$dirName"/||die
      rm -rf "$installPath"/*||die
      find "$installPath"/ -name '.*' | xargs rm -rf||die
  fi
  echo
}


fixPermissions() {
  printinfo "Asegurándonos que todo pertenece a ${fermentrackUser}"
  chown -R ${fermentrackUser}:${fermentrackUser} "$installPath"||die
  # Set sticky bit! nom nom nom
  find "$installPath" -type d -exec chmod g+rwxs {} \;||die
  echo
}


# Clone Fermentrack repositories
cloneRepository() {
  printinfo "Descargando el código de $package_name más reciente..."
  cd "$installPath"
  if [ "$github_repo" != "master" ]; then
    sudo -u ${fermentrackUser} -H git clone -b ${github_branch} ${github_repo} "$installPath/fermentrack"||die
  else
    sudo -u ${fermentrackUser} -H git clone ${github_repo} "$installPath/fermentrack"||die
  fi
  echo
}


createPythonVenv() {
  # Set up virtualenv directory
  printinfo "Creando el directorio virtualenv..."
  cd "$installPath"
  # For specific gravity sensor support, we want --system-site-packages
  sudo -u ${fermentrackUser} -H virtualenv --system-site-packages "venv"
  echo
}

setPythonSetcap() {
  printinfo "Activando python para utilizar bluetooth sin necesidad de ser root"

#  if [ -a "$installPath/venv/bin/python" ]; then
#    setcap cap_net_raw+eip "$installPath/venv/bin/python"
#  fi

  if [ -a "$installPath/venv/bin/python2" ]; then
    setcap cap_net_raw+eip "$installPath/venv/bin/python2"
  fi
}


forcePipReinstallation() {
  # This forces reinstallation of pip within the virtualenv in case the environment has a "helpful" custom version
  # (I'm looking at you, ubuntu/raspbian...)
  printinfo "Forzando la instalación de pip en el virtualenv"
  sudo -u ${fermentrackUser} -H bash "$myPath"/force-pip-install.sh -p "${installPath}/venv/bin/activate"
}

# Create secretsettings.py file
makeSecretSettings() {
  printinfo "Ejecutando el script make_secretsettings.sh de la repo"
  if [ -a "$installPath"/fermentrack/utils/make_secretsettings.sh ]; then
    cd "$installPath"/fermentrack/utils/
    sudo -u ${fermentrackUser} -H bash "$installPath"/fermentrack/utils/make_secretsettings.sh
  else
    printerror "No se puede encontrar fermentrack/utils/make_secretsettings.sh!"
    # TODO: decide if this is a fatal error or not
    exit 1
  fi
  echo
}


# Run the upgrade script within Fermentrack
runFermentrackUpgrade() {
  printinfo "Ejecutando el script upgrade.sh de la repo para finalizar la instalación."
  printinfo "Esto puede tomar MUCHOS minutos y no se verá nada nuevo en la pantalla hasta su finalización, sé paciente..."
  if [ -a "$installPath"/fermentrack/utils/upgrade.sh ]; then
    cd "$installPath"/fermentrack/utils/
    sudo -u ${fermentrackUser} -H bash "$installPath"/fermentrack/utils/upgrade.sh &>> install.log
  else
    printerror "No se puede encontrar fermentrack/utils/upgrade.sh!"
    exit 1
  fi
  echo
}


# Check for insecure SSH key
# TODO: Check if this is still needed, newer versions of rasbian don't have this problem.
fixInsecureSSH() {
  defaultKey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLNC9E7YjW0Q9btd9aUoAg++/wa06LtBMc1eGPTdu29t89+4onZk1gPGzDYMagHnuBjgBFr4BsZHtng6uCRw8fIftgWrwXxB6ozhD9TM515U9piGsA6H2zlYTlNW99UXLZVUlQzw+OzALOyqeVxhi/FAJzAI9jPLGLpLITeMv8V580g1oPZskuMbnE+oIogdY2TO9e55BWYvaXcfUFQAjF+C02Oo0BFrnkmaNU8v3qBsfQmldsI60+ZaOSnZ0Hkla3b6AnclTYeSQHx5YqiLIFp0e8A1ACfy9vH0qtqq+MchCwDckWrNxzLApOrfwdF4CSMix5RKt9AF+6HOpuI8ZX root@raspberrypi"

  if grep -q "$defaultKey" /etc/ssh/ssh_host_rsa_key.pub; then
    printinfo "Reemplazando las llaves SSH por defecto. Necesitas eliminar las llaves anteriores de los hosts y clientes que se conectaran anteriormente a la RPi."
    if rm -f /etc/ssh/ssh_host_* && dpkg-reconfigure openssh-server; then
      printinfo "Las llaves SSH fueron reemplazadas."
      echo
    else
      printwarn "Imposible reemplazar las llaves SSH. Probablemente quieras tomarte un tiempo para hacer sto tu mismo."
    fi
  fi
}


# Set up nginx
setupNginx() {
  printinfo "Copinado configuración de nginx a /etc/nginx y activando."
  rm -f /etc/nginx/sites-available/default-fermentrack &> /dev/null
  # Replace all instances of 'brewpiuser' with the fermentrackUser we set and save as the nginx configuration
  sed "s/brewpiuser/${fermentrackUser}/" "$myPath"/nginx-configs/default-fermentrack > /etc/nginx/sites-available/default-fermentrack
  rm -f /etc/nginx/sites-enabled/default &> /dev/null
  ln -sf /etc/nginx/sites-available/default-fermentrack /etc/nginx/sites-enabled/default-fermentrack
  service nginx restart
}


setupCronCircus() {
  # Install CRON job to launch Circus
  printinfo "Ejecuantado el script updateCronCircus.sh de la repo"
  if [ -f "$installPath"/fermentrack/utils/updateCronCircus.sh ]; then
    sudo -u ${fermentrackUser} -H bash "$installPath"/fermentrack/utils/updateCronCircus.sh add2cron
    printinfo "Comenzando el proceso circus."
    sudo -u ${fermentrackUser} -H bash "$installPath"/fermentrack/utils/updateCronCircus.sh start
  else
    # whoops, something is wrong...
    printerror "No se puede encontrar updateCronCircus.sh!"
    exit 1
  fi
  echo
}


installationReport() {
#  MYIP=$(/sbin/ifconfig|egrep -A 1 'eth|wlan'|awk -F"[Bcast:]" '/inet addr/ {print $4}')
  MYIP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
  echo "¡Instalación de Fermentrack finalizada!"
  echo "====================================================================================================="
  echo "Puedes mirar el log para encontrar cualquier error, u otra cosa, pero tu intalación está completa"
  echo
  echo "El usuario fermentrack se creó sin password. Usa 'sudo -u ${fermentrackUser} -i'"
  echo "desde este usuario para acceder al usuario fermentrack"
  echo "Para ver Fermentrack, ingresa a http://${MYIP} en tu navegador"
  echo
  echo " - Frontend de Fermentrack : http://${MYIP}"
  echo " - Usuario Fermentrack	   : ${fermentrackUser}"
  echo " - Ruta de instalación     : ${installPath}/fermentrack"
  echo " - Versión de Fermentrack  : $(git -C ${installPath}/fermentrack log --oneline -n1)"
  echo " - Versión del instalador  : ${scriptversion}"
  echo " - Herram. de instalación  : ${myPath}"
  echo ""
  echo "Happy Brewing! ;)"
  echo ""
}


## ------------------- Script "main" starts here -----------------------
# Create install log file
verifyRunAsRoot
welcomeMessage

# This one should remove color escape codes from log, but it needs some more
# work so the EOL esc codes also get stripped.
# exec > >( tee >( sed 's/\x1B\[[0-9;]*[JKmsu]//g' >> install.log ) )
exec > >(tee -i install.log)
exec 2>&1

if [[ ${INTERACTIVE} -eq 1 ]]; then  # Don't ask questions if we're running in noninteractive mode
    printinfo "Para aceptar la respuesta por defecto, sólo presione Enter."
    printinfo "La respuesta por defecto está en MAYÚSCULA en la pregunta Yes/No: [Y/n]"
    printinfo "o se muestra entre corchetes para otras preguntas: [por_defecto]"
    echo

    date=$(date)
    read -p "La hora está puesta como $date. ¿Es correcto? [Y/n]" choice
    case "$choice" in
      n | N | no | NO | No )
        dpkg-reconfigure tzdata;;
      * )
    esac

    printinfo "Todos los scriptss asociados con BrewPi & Fermentrack están ahora instalados en el directorio home del usuario"
    printinfo "Pulsando 'enter' aceptas la opción por defecto entre [corchetes] (recomendado)."
    printwarn "¡Cualquier dato en la carpeta home del usuario se ELIMINARÁ!"
    echo
    read -p "¿Bajo que usuario se instalará BrewPi/Fermentrack? [fermentrack]: " fermentrackUser
    if [ -z "${fermentrackUser}" ]; then
      fermentrackUser="fermentrack"
    else
      case "${fermentrackUser}" in
        y | Y | yes | YES| Yes )
            fermentrackUser="fermentrack";; # accept default when y/yes is answered
        * )
            ;;
      esac
    fi
else  # If we're in non-interactive mode, default the user
    fermentrackUser="fermentrack"
fi

installPath="/home/${fermentrackUser}"
scriptversion=$(git log --oneline -n1)
printinfo "Configurando el usuario ${fermentrackUser}"
printinfo "Configurado en el directorio $installPath"
echo


verifyInternetConnection
verifyInstallerVersion
getAptPackages
verifyFreeDiskSpace
verifyInstallPath
createConfigureUser
backupOldInstallation
fixPermissions
cloneRepository
fixPermissions
createPythonVenv
setPythonSetcap
forcePipReinstallation
makeSecretSettings
runFermentrackUpgrade
fixInsecureSSH
setupNginx
setupCronCircus
installationReport
sleep 1s
