# Microphone

Install
```
pkg install snd sndio
```

add in /boot/loader.conf
```
snd_driver_load="YES"
```

# Webcam

Install
```
sudo pkg install v4l-utils v4l_compat webcamd
```

Enable wemcamd at boot time
```
sudo sysrc kld_list+=cuse
sudo sysrc webcamd_enable="YES"
```

Add the user to the webcamd group
```
sudo pw groupmod webcamd -m USERNAME
```

Identify which device entry the webcam is.
```
sudo webcamd
```

Add the webcam to rc.conf file
```
sudo sysrc webcamd_0_flags="-d ugen1.6”
```
or the full description
```
sudo sysrc webcamd_0_flags="-d ugen0.2 -N vendor-0x046d-HD-Pro-Webcam-C920 -S E03A659F -M 0"
```

Show webcamd usage:
```
webcamd -h
```

Configure USB mounting to the user.
```
sudo sysctl vfs.usermount=1
```

Test the webcam
```
sudo pkg install pwcview
pwcview -s svga -f 30
```
