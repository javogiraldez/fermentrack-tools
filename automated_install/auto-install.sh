#!/usr/bin/env bash

# auto-install.sh
#
# This script attempts to automatically download fermentrack-tools and use install.sh to install Fermentrack.
# It can be run via curl (See install_curl_command below) which enables the user to install everything with one
# command.

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

package_name="Fermentrack"
install_curl_url="goo.gl/1ccpUR"
install_curl_command="curl -L goo.gl/1ccpUR | sudo bash"
tools_name="fermentrack-tools"
tools_repo_url="https://github.com/javogiraldez/fermentrack-tools.git"

# Set scriptPath to the current script path
unset CDPATH
scriptPath="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"



#######
#### Error capturing functions - Originally from http://mywiki.wooledge.org/BashFAQ/101
#######
warn() {
  local fmt="$1"
  command shift 2>/dev/null
  echo -e "$fmt\n" "${@}"
  echo -e "\n*** ERROR ERROR ERROR ERROR ERROR ***\n----------------------------------\nSee above lines for error message\nSetup NOT completed\n"
}

die () {
  local st="$?"
  warn "$@"
  exit "$st"
}


#######
#### Compatibility checks & tests
#######
verifyRunAsRoot() {
    # verifyRunAsRoot does two things - First, it checks if the script was run by a root user. Assuming it wasn't,
    # then it attempts to relaunch itself as root.


    if [[ ${EUID} -eq 0 ]]; then
        echo "::: Este script es ejecutado como root. Continuando con la instalación."
    else
        echo "::: Este script fue ejecutado sin privilegios root. Se instalarán y actualizarán varios paquetes, y el"
        echo "::: script llamado dentro de ${tools_name} crea una cuenta de usuario y actualiza configuraciones del"
        echo "::: sistema . Para continuar este script usará 'sudo' para reejecutarse como root. Por favor comprueba"
        echo "::: el funcionamiento del script (como tambien el script de instalación ${tools_name} por cualquier"
        echo "::: comprobación que requiera. Asegúrate de acceder a este script (and ${tools_name}) de una fuente fiable."
        echo ":::"

        if command -v sudo &> /dev/null; then
            # TODO - Make this require user confirmation before continuing
            echo "::: El script se ejecutará nuevamente utilizando sudo."
            exec curl -L $install_curl_url | sudo bash "$@"
            exit $?
        else
            echo "::: The sudo utility does not appear to be available on this system, and thus installation cannot continue."
            echo "::: Please run this script as root and it will be automatically installed."
            echo "::: You should be able to do this by running '${install_curl_command}'"
            exit 1
        fi
    fi

}

verifyFreeDiskSpace() {
  echo "::: Verificando espacio disponible en el disco..."
  local required_free_kilobytes=512000
  local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # - Unknown free disk space , not a integer
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    echo ":: Espacio libre en el disco, DESCONOCIDO!"
    echo ":: No somos capaces de determinar el espacio libre disponible en el sistema."
    exit 1
  # - Insufficient free disk space
  elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
    echo ":: Espacio en el disco, INSUFICIENTE!"
    echo ":: Tu sistema aparentemente tiene poco espacio. ${package_name} recomienda un mínimo de $required_free_kilobytes KB."
    echo ":: Sólo tienes ${existing_free_kilobytes} KB libres."
    echo ":: Si es una instalación limpia, debería expandir tu disco."
    echo ":: Prueba usando 'sudo raspi-config', y seleccioando 'expand file system option'"
    echo ":: Despues de reiniciar, ejecuta la instalación otra vez. (${install_curl_command})"

    echo "Espacio libre en el disco, insuficiente, Saliendo..."
    exit 1
  fi
}

#######
#### Installation functions
#######

# getAptPackages runs apt-get update, and installs the basic packages we need to continue the Fermentrack install
# (git-core, build-essential, python-dev, python-virtualenv). The rest can be installed by fermentrack-tools/install.sh
getAptPackages() {
    echo -e "::: Instalando dependencias utilizando apt-get"
    lastUpdate=$(stat -c %Y /var/lib/apt/lists)
    nowTime=$(date +%s)
    if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
        echo "::: La última 'apt-get update' fue hace tiempo. Actualizando ahora."
        sudo apt-get update &> /dev/null||die
        echo ":: 'apt-get update' ejecutado correctamente."
    fi

    sudo apt-key update &> /dev/null||die
    echo "::: 'apt-key update' ejecutado correctamente."

    # Installing the nginx stack along with everything we need for circus, etc.
    echo "::: apt está actualizado - instalando git-core, build-essential, python-dev, y python-virtualenv."
    echo "::: Esto puede tomar unos minutos y no se verá nada nuevo en la pantalla hasta su finalización..."
    sudo apt-get install -y git-core build-essential python-dev python-virtualenv &> /dev/null || die
    echo ":: Todos los paquetes instalados correctamente."
}

handleExistingTools() {
  echo -e ":::: Una instancia existente de ${tools_name} se encontró en ${scriptPath}/${tools_name}"
  echo -e ":::: Moviendo a ${scriptPath}/${tools_name}.old/"
  rm -r ${tools_name}.old &> /dev/null
  mv ${tools_name} ${tools_name}.old||die
  echo -e ":::: Movido correctamente. Clonando nuevamente."
  git clone ${tools_repo_url} "${tools_name}" -q &> /dev/null||die
}

cloneFromGit() {
    echo -e "::: Clonando ${tools_name} repo de GitHub en ${scriptPath}/${tools_name}"
    git clone ${tools_repo_url} "${tools_name}" -q &> /dev/null||handleExistingTools
    echo ":: La repo se clonó correctamente."
}
launchInstall() {
    echo "::: Ahora comenzará a instalar ${package_name} usando el script 'install.sh' que fue creado en"
    echo -e "::: ${scriptPath}/${tools_name}/install.sh"
    echo -e "::: Si el script de instalación no se completa correctamente, por favor ejecuta otra vez el script citado."
    echo -e "::: "
    echo -e "::: Ejecutando el instalador de ${package_name}."
    cd ${tools_name}
    # The -n flag makes install.sh non-interactive
    sudo bash ./install.sh -n
    echo -e "::: La instalación automatica ha finalizado. Si no se realizó correctamente,"
    echo -e "::: ejecuta otra vez el script que se descargó en:"
    echo -e "::: ${scriptPath}/${tools_name}/install.sh"
}


#######
### Now, for the main event...
#######
verifyRunAsRoot
verifyFreeDiskSpace
getAptPackages
cloneFromGit
launchInstall

