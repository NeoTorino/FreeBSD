#!/usr/local/bin/zsh

set -eu  # Exit on error and unset variables

# Check if script is run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run this script as root";
  exit 0;
fi

# VM Configuration
VM=(vmfbsd01 vmfbsd02)
CPU=(1 1)
RAM=(1024 1024)   # in MB
HDName=(vmfbsd01.img vmfbsd02.img)
HDSize=(15G 15G)
HDType=(raw raw)
TAP=(tap0 tap1)

HD_DIR="/vms/qemu/vm"
CDROM="/vms/qemu/iso/fbsd.iso"
ORDER_BOOT="cd"
BRIDGE="bridge0"
INET="10.0.0.1/24"

#### End configuration

# Reference length from vmName
ref_len=${#VM[@]}

# Define an associative array of names and actual lengths
typeset -A array_lengths
array_lengths=(
  CPU     ${#CPU[@]}
  RAM     ${#RAM[@]}
  HDName  ${#HDName[@]}
  HDSize  ${#HDSize[@]}
  HDType  ${#HDType[@]}
  TAP     ${#TAP[@]}
)

# Check lengths
for name in "${(@k)array_lengths}"; do
  if (( array_lengths[$name] != ref_len )); then
    echo "**Error. Array '$name' has length ${array_lengths[$name]}, expected $ref_len"
    exit 1;
  fi
done

interface_exists(){
  interfaces=($(ifconfig -l))
  # Check if value exists in the array
  for i in "${interfaces[@]}"; do
    if [[ "$i" == "$1" ]]; then
      return 0  # true
    fi
  done
  return 1  # false
}

# Function to display help
show_help() {
  echo "Usage: $0 [options] <args>"
  echo
  echo "Arguments:"
  echo "  r, run        Create and run the virtual machines."
  echo "  d, delete     Delete the network interfaces."
  echo "  h, help       Show this help message and exit"
}

# Check if no arguments were passed
if (( $# == 0 )); then
  echo "No arguments provided."
  show_help
  exit 1

elif [[ "$1" == "h" || "$1" == "help" ]]; then
  show_help

elif [[ "$1" == "d" || "$1" == "d" ]]; then
  # delete the network interfaces
  for ((j = 1; j <= ref_len; j++)); do
    if interface_exists $TAP[$j]; then
      echo "Deleting interface: ${TAP[$j]}"
      ifconfig $TAP[$j] destroy
    fi
    
  done

  if interface_exists $BRIDGE; then
    echo "Deleting interface: $BRIDGE"
    ifconfig $BRIDGE destroy
  fi

else
  # create and run the virtual machines

  # Type of HD
  # raw disk, for performance.
  # qemu-img create -f raw  hd.img   20G
  #
  # qcow2 disk, for additional features (snapshots, compression, and encryption). cow2 means copy on write.
  # qemu-img create -f qcow2 -o preallocation=full,cluster_size=512K,lazy_refcounts=on right.qcow2 20G

  # Bridge interface

  if ! interface_exists $BRIDGE; then
    echo "Creating interface $BRIDGE";
    ifconfig $BRIDGE create
    ifconfig $BRIDGE inet $INET up
  fi

  # TAP interface settings
  up_on_open=$(sysctl -n net.link.tap.up_on_open)
  user_open=$(sysctl -n net.link.tap.up_on_open)

  if (( up_on_open != 1 )); then
    sysctl net.link.tap.up_on_open=1
  fi
  if (( user_open != 1 )); then
    sysctl net.link.tap.user_open=1
  fi

  for ((j = 1; j <= ref_len; j++)); do
    
    echo "Configuring VM: ${VM[$j]}";

    # HD
    hdpath="$HD_DIR/$HDName[$j]"
    if [[ ! -e "$hdpath" ]]; then
      qemu-img create -q -f "$HDType[$j]" "$hdpath" "$HDSize[$j]"
      echo "Created HD: ${hdpath}. Type: ${HDType[$j]}. Size: ${HDSize[$j]}"
      ORDER_BOOT="d"
    fi

    # Interface
    if ! interface_exists $TAP[$j]; then
      echo "Creating interface: $TAP[$j]";
      ifconfig $TAP[$j] create;
      ifconfig $TAP[$j] up
      ifconfig $BRIDGE addm $TAP[$j]
    fi 

    # Generate a random MAC address.
    mac=$(env LC_ALL=C tr -dc A-F0-9 < /dev/urandom | head -c 12 | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/');
    #mac2=$(openssl rand -hex 6 |sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/' )

    node="img_${VM[$j]}";

    # Run the virtual machine
    /usr/local/bin/qemu-system-x86_64  -monitor none \
      -cpu qemu64 \
      -vga std \
      -m "$RAM[$j]" \
      -smp "$CPU[$j]"   \
      -cdrom "$CDROM" \
      -boot order=$ORDER_BOOT,menu=on \
      -blockdev driver=file,aio=threads,node-name=$node,filename=$hdpath \
      -blockdev driver="${HDType[$j]}",node-name=drive0,file=$node \
      -device virtio-blk-pci,drive=drive0,bootindex=1  \
      -netdev tap,id=nd0,ifname=$TAP[$j],script=no,downscript=no,br="${BRIDGE}" \
      -device e1000,netdev=nd0,mac=$mac \
      -name $VM[$j] &

    sleep 1;

  done  

fi # create and run

exit 0;
