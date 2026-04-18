The device name is different on this VM. Let's find the correct one:


lsblk
It's likely /dev/nvme0n1 or /dev/sda. Once you see the output, run the correct commands. Most likely:


# If nvme-based (most modern EC2):
sudo growpart /dev/nvme0n1 1 && sudo resize2fs /dev/nvme0n1p1

# If sda-based:
sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1

sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1