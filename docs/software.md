# Installing Software
## Step 1 - Install OS
Follow [these insstruction](os.md)

## Step 2 - base software
    curl -s https://raw.githubusercontent.com/fancydrones/x500-cm4/main/install/install_base.sh | sh -

## Step 3 - reboot
    sudo reboot

## Step 4 - specific software
    curl -s https://raw.githubusercontent.com/fancydrones/x500-cm4/main/install/install_rpiuav.sh | sh -

## Step 5 - join Zerotier network
Follow [instructions here](zerotier.md)