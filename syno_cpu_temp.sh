#!/usr/bin/env bash
#----------------------------------------------------------
# Display CPU temperature and each core's temperature
#
# Github: https://github.com/007revad/Synology_CPU_temp
# Script verified at https://www.shellcheck.net/
#----------------------------------------------------------

scriptver="v2.3.7"
script=Synology_CPU_temp
repo="007revad/Synology_CPU_temp"
scriptname=syno_cpu_temp

# Show script version
#echo -e "$script $scriptver\ngithub.com/$repo\n"
echo "$script $scriptver"

# Get NAS model
model=$(cat /proc/sys/kernel/syno_hw_version)

# Get DSM full version
productversion=$(/usr/syno/bin/synogetkeyvalue /etc.defaults/VERSION productversion)
buildphase=$(/usr/syno/bin/synogetkeyvalue /etc.defaults/VERSION buildphase)
buildnumber=$(/usr/syno/bin/synogetkeyvalue /etc.defaults/VERSION buildnumber)
smallfixnumber=$(/usr/syno/bin/synogetkeyvalue /etc.defaults/VERSION smallfixnumber)

# Show DSM full version and model
if [[ $buildphase == GM ]]; then buildphase=""; fi
if [[ $smallfixnumber -gt "0" ]]; then smallfix="-$smallfixnumber"; fi
echo -e "${model} DSM $productversion-$buildnumber$smallfix $buildphase"

# Get DSM major version
dsm=$(get_key_value /etc.defaults/VERSION majorversion)

# Read variables from syno_cpu_temp.conf
if [[ -f $(dirname -- "$0";)/${scriptname}.conf ]];then
    Log_Directory=$(synogetkeyvalue "$(dirname -- "$0";)/${scriptname}.conf" Log_Directory)
    Log=$(synogetkeyvalue "$(dirname -- "$0";)/${scriptname}.conf" Log)
else
    echo "${scriptname}.conf file missing!"
    exit 1
fi

# Check if backup directory exists
if [[ ${Log,,} == "yes" ]]; then
    if [[ ! -d $Log_Directory ]]; then
        echo "Log directory not found:"
        echo "$Log_Directory"
        echo "Check your setting in syno_cpu_temp.conf"
        exit 1
    else
        echo -e "Logging to $Log_Directory\n"
        now="$(date +"%Y-%m-%d %H:%M:%S") - "
        Log_File="${Log_Directory}/${scriptname}.log"
    fi
fi

#------------------------------------------------------------------------------
# Check latest release with GitHub API

# Get latest release info
# Curl timeout options:
# https://unix.stackexchange.com/questions/94604/does-curl-have-a-timeout
#release=$(curl --silent -m 10 --connect-timeout 5 \
#    "https://api.github.com/repos/$repo/releases/latest")

# Use wget to avoid installing curl in Ubuntu
release=$(wget -qO- -q --connect-timeout=5 \
    "https://api.github.com/repos/$repo/releases/latest")

# Release version
tag=$(echo "$release" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
#shorttag="${tag:1}"

if ! printf "%s\n%s\n" "$tag" "$scriptver" |
        sort --check=quiet --version-sort >/dev/null ; then
    echo -e "\nThere is a newer version of this script available." |& tee -a "$Log_File"
    echo -e "Current version: ${scriptver}\nLatest version:  $tag" |& tee -a "$Log_File"
fi

#------------------------------------------------------------------------------

pad_len(){ 
    #echo ${1}   # debug
    #echo ${#1}  # debug

    if [[ ${#1} -eq "1" ]]; then
        pad="  "
    elif [[ ${#1} -eq "2" ]]; then
        pad=" "
    else
        pad=""
    fi
}

# shellcheck disable=SC2329  # Don't warn This function is never invoked
pad_len_amd(){ 
    #echo ${1}   # debug
    #echo ${#1}  # debug

    # AMD k10 temps can have 3 decimal places
    if [[ ${#1} -eq "1" ]]; then
        pad="      "
    elif [[ ${#1} -eq "2" ]]; then
        pad="     "
    elif [[ ${#1} -eq "3" ]]; then
        pad="    "
    elif [[ ${#1} -eq "4" ]]; then
        pad="   "
    elif [[ ${#1} -eq "5" ]]; then
        pad="  "
    elif [[ ${#1} -eq "6" ]]; then
        pad=" "
    else
        pad=""
    fi
}

c2f(){ 
    # Celsius to Fahrenheit 
    # F = (C x 9/5) + 32
    local a
    local b

    a=$(echo "${1%.*}" | awk '{print ($1 * 1.8)}')
    #echo "a: $a"  # debug

    if [[ $1 == *.* ]]; then
        d="${1##*.}"
    fi
    if [[ ${#d} -eq 1 ]]; then
        b=$(echo "${1##*.}" | awk '{print (($1 * 1.8) / 10)}')
    elif [[ ${#d} -eq 2 ]]; then
        b=$(echo "${1##*.}" | awk '{print (($1 * 1.8) / 100)}')
    elif [[ ${#d} -eq 3 ]]; then
        b=$(echo "${1##*.}" | awk '{print (($1 * 1.8) / 1000)}')
    fi
    #echo "b: $b"  # debug

    if [[ -n $b ]]; then
        f=$(echo "$a" "$b" | awk '{print (($1 + $2) + 32)}')
    else
        f=$(echo "$a" | awk '{print ($1 + 32)}')
    fi
    #echo "f: $f"  # debug

    echo "$f"
}

# shellcheck disable=SC2329  # Don't warn This function is never invoked
f2c(){ 
    # Fahrenheit to Celsius - not used
    # C = (F – 32) x 5/9
    #c=$(($((1 -32)) * 1.8))
    echo "$f"
}

# Get CPU model
cpu_model=$(grep -E '^model name' /proc/cpuinfo | uniq | cut -d":" -f2 | xargs)
if [[ -z $cpu_model ]]; then
    cpu_model=$(grep -E '^Processor' /proc/cpuinfo | uniq | cut -d":" -f2 | xargs)
fi

# Get CPU max temp (high threshold)
max=$(grep . /sys/class/hwmon/hwmon*/temp*_max 2>/dev/null | cut -d":" -f2 | uniq)
crit=$(grep . /sys/class/hwmon/hwmon*/temp*_crit 2>/dev/null | cut -d":" -f2 | uniq)
marvl=$(cat /sys/class/hwmon/hwmon0/device/temp1_max 2>/dev/null)
if [[ -n $max ]]; then
    #maxtemp="Max temp threshold: $((max /1000))°C  $(c2f $((max /1000)))°F"
    pad_len "$((max /1000))"
    max_temp="$((max /1000))°C"
    max_tempf="$(c2f $((max /1000)))°F"
elif [[ -n $crit ]]; then
    #maxtemp="Critical threshold: $((crit /1000))°C  $(c2f $((crit /1000)))°F"
    pad_len "$((crit /1000))"
    max_temp="$((crit /1000))°C"
    max_tempf="$(c2f $((crit /1000)))°F"

elif [[ -n $marvl ]]; then
    #maxtemp="Max temp threshold: ${marvl}°C  $(c2f "$marvl")°F"
    pad_len "$marvl"
    max_temp="${marvl}°C"
    max_tempf="$(c2f "$marvl")°F"
fi
if [[ ${max}${crit}${marvl} ]]; then
    maxtemp="Max temp threshold: $max_temp $pad $max_tempf"
fi

# Get DSM shutdown temp
# Old style scemd.xml
sdt1=$(grep -i shutdown /usr/syno/etc.defaults/scemd.xml |\
    grep cpu_temperature | uniq | cut -d">" -f2 | cut -d"<" -f1)
# New style scemd.xml
sdt2=$(grep -i shutdown_temp /usr/syno/etc.defaults/scemd.xml |\
    grep cpu | uniq | awk  '{print $(NF-1)}' |  cut -d"\"" -f2)

#echo "sdt1: $sdt1"  # debug
#echo "sdt2: $sdt2"  # debug
#sdt2="123"          # debug test 3 digit temp  toasty
#sdt2="9"            # debug test 1 digit temp  brrr!

if [[ -n $sdt1 ]]; then
    pad_len "$sdt1"
    shutdown_temp="${sdt1}°C"
    shutdown_tempf="$(c2f "$sdt1")°F"
elif [[ -n $sdt2 ]]; then
    pad_len "$sdt2"
    shutdown_temp="${sdt2}°C"
    shutdown_tempf="$(c2f "$sdt2")°F"
fi

if [[ ${Log,,} == "yes" ]]; then
    # Add header to log if log file does not already exist
    if [[ ! -f "$Log_File" ]]; then
        echo "$script $scriptver" > "$Log_File"
        echo -e "${model} DSM $productversion-$buildnumber$smallfix $buildphase" >> "$Log_File"
        # Log CPU model
        #echo >> "$Log_File"
        if [[ -n $cpu_model ]]; then
            echo "$cpu_model" >> "$Log_File"
        else
            echo "Unknown CPU model" >> "$Log_File"
        fi
        # Log CPU max temp (high threshold)
        if [[ -n $maxtemp ]]; then echo "$maxtemp" >> "$Log_File"; fi
        # Log DSM shutdown temp
        if [[ -n $shutdown_temp ]]; then
            echo "DSM shutdown Temp:  $shutdown_temp $pad $shutdown_tempf" >> "$Log_File"
        fi
        echo "" >> "$Log_File"
    fi
else
    echo ""
    Log_File="/dev/null"
fi

# Get CPU vendor & set style
if grep Intel /proc/cpuinfo >/dev/null; then
    vendor="Intel"
    style="intel"
elif grep AMD /proc/cpuinfo >/dev/null; then
    vendor="AMD"
    style="amd"
elif grep Realtek /proc/cpuinfo >/dev/null; then
    vendor="Realtek"
    style="intel"
elif grep Marvell /proc/cpuinfo >/dev/null; then
    vendor="Marvell"
    style="marvell"
elif grep Annapurna /proc/cpuinfo >/dev/null; then
    vendor="Annapurna"
    style="intel"
elif grep STM /proc/cpuinfo >/dev/null; then
    vendor="STM"
    style="intel"
elif grep Mindspeed /proc/cpuinfo >/dev/null; then
    vendor="Mindspeed"
    style="intel"
elif grep Freescale /proc/cpuinfo >/dev/null; then
    vendor="Freescale"
    style="intel"
else
    vendor="$(grep 'vendor_id' /proc/cpuinfo | uniq | cut -d":" -f2 | xargs)"
fi

supported_vendors=("intel" "amd" "realtek" "marvell""annapurna" "stm" "mindspeed" "freescale")

if [[ ! ${supported_vendors[*]} =~ "${vendor,,}" ]]; then
    echo "$vendor not supported yet." |& tee -a "$Log_File"
    echo "Create a Github issue to get $vendor CPUs added." |& tee -a "$Log_File"
    exit
fi

# Show CPU model
grep 'model name' /proc/cpuinfo | uniq | cut -d":" -f2 | xargs

# Show CPU max temp (high threshold)
if [[ -n $maxtemp ]]; then echo "$maxtemp"; fi

# Show DSM shutdown temp
if [[ -n $shutdown_temp ]]; then
    echo "DSM shutdown Temp:  $shutdown_temp $pad $shutdown_tempf"
fi

# Get number of CPUs
cpu_qty=$(grep 'physical id' /proc/cpuinfo | uniq | awk '{printf $4}')
#cpu_qty=$((cpu_qty +1))  # test multiple CPUs

# shellcheck disable=SC2329  # Don't warn This function is never invoked
show_cpu_number(){ 
    # echo [CPU 0] or [CPU 1] etc if more than 1 CPU
    if [[ $cpu_qty -gt "0" ]]; then
        # Show CPU number
        echo -en "\n${now}" >> "$Log_File"
        echo -e "[CPU $c]" >> "$Log_File"
        echo -e "\n[CPU $c]"
    else
        #if [[ ${vendor,,} != "amd" ]]; then
            #echo "" |& tee -a "$Log_File"
            echo ""
        #fi
    fi
}

# shellcheck disable=SC2329  # Don't warn This function is never invoked
show_intel_temps(){ 
    # $1 for DSM 7 is "/sys/class/hwmon/hwmon"
    # $1 for DSM 6 is "/sys/bus/platform/devices/coretemp."
    c=0
    while [[ ! $c -gt $cpu_qty ]]; do
        show_cpu_number

        x=1
        while [ "$x" -lt $(($(nproc) +2)) ]; do
            # Show core $x temp for CPU $c
            if [ -f "${1}$c/temp${x}_input" ]; then
                echo -n "${now}" >> "$Log_File"
                if [ -f "${1}$c/temp${x}_label" ]; then
                    printf %s "$(cat "${1}$c/temp${x}_label"): " |& tee -a "$Log_File"
                else
                    # Some Intel CPUs don't have tempN_label
                    echo -n "Core $((x -1)): " |& tee -a "$Log_File"
                fi
                ctmp="$(awk '{printf $1/1000}' "${1}$c/temp${x}_input")"
                ftmp="$(c2f "$ctmp")"
                echo "${ctmp}°C  ${ftmp}°F" |& tee -a "$Log_File"
            fi
            x=$((x +1))
        done
        c=$((c +1))
    done
}

# shellcheck disable=SC2329  # Don't warn This function is never invoked
show_amd_temps(){ 
    # $1 for DSM 7 is "/sys/class/hwmon/hwmon"
    # $1 for DSM 6 is "/sys/bus/platform/devices/coretemp."
    c=0
    while [[ ! $c -gt $cpu_qty ]]; do
        show_cpu_number

        # Show k10temp
        if [[ -f "${1}$c/name" ]]; then
            echo -n "${now}" >> "$Log_File"
            printf %s "$(cat "${1}$c/name"):  " |& tee -a "$Log_File"

            #ctmp="$(awk '{printf $1/1000}' "${1}$c/temp1_input")"
            #ftmp="$(c2f "$ctmp")"
            #echo "${ctmp}°C  ${ftmp}°F" |& tee -a "$Log_File"

            ctmp1="$(awk '{printf $1/1000}' "${1}$c/temp1_input")"
            pad_len_amd "$ctmp1"
            ctmp="${ctmp1}°C"
            ftmp="$(c2f "$ctmp")°F"
            # Show k10 temp
            echo "$ctmp   $ftmp"
            # Log k10 temp
            echo "$ctmp $pad $ftmp" >> "$Log_File"
        fi
        c=$((c +1))
    done
}

# shellcheck disable=SC2329  # Don't warn This function is never invoked
show_marvell_temps(){ 
    # $1 for DSM 7 is "/sys/class/hwmon/hwmon0/device"
    # $1 for DSM 6 is "/sys/bus/platform/devices/coretemp." ???

    # Show T-junction temp
    if [[ -f "${1}/temp1_label" ]]; then
        echo -n "${now}" >> "$Log_File"
        printf %s "$(cat "${1}/temp1_label"):  " |& tee -a "$Log_File"
        ctmp="$(printf %s "$(cat "${1}/temp1_input")")"
        ftmp="$(c2f "$ctmp")"
        echo "${ctmp}°C  ${ftmp}°F" |& tee -a "$Log_File"
    fi
}

if [[ $dsm -gt "6" ]]; then
    if [[ $style == "marvell" ]]; then
        show_"${style}"_temps "/sys/class/hwmon/hwmon0/device"
    else
        show_"${style}"_temps "/sys/class/hwmon/hwmon"
    fi
elif [[ $dsm -eq "6" ]]; then
    show_"${style}"_temps "/sys/bus/platform/devices/coretemp."
else
    echo "Unknown or unsupported DSM version ${dsm}!" |& tee -a "$Log_File"
fi

echo ""

exit

