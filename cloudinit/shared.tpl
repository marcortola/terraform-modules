#cloud-config

timezone: Etc/UTC

package_update: true
package_upgrade: true

manage_etc_hosts: true

users:
  - default
  - name: kamal
    uid: 1000
    lock_passwd: true
    shell: /bin/bash
    groups:
      - docker
      - sudo
    sudo:
      - ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_authorized_key}

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - git
  - htop
  - ntp
  - unattended-upgrades
  - docker.io

write_files:
  - path: /etc/apt/apt.conf.d/20auto-upgrades
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Unattended-Upgrade "1";
  - path: /etc/sysctl.d/10-disable-ipv6.conf
    permissions: 0644
    owner: root
    content: |
      net.ipv6.conf.default.disable_ipv6=1
      net.ipv6.conf.all.disable_ipv6=1
      net.ipv6.conf.eth0.disable_ipv6 = 1
      net.ipv6.conf.lo.disable_ipv6=1
  - path: /etc/ssh/sshd_config
    content: |
      Port 937
      LoginGraceTime 120
      PermitRootLogin no
      PermitEmptyPasswords no
      PasswordAuthentication no
      StrictModes yes
      DebianBanner no
      PubkeyAuthentication yes
      IgnoreRhosts yes
      HostbasedAuthentication no
      ChallengeResponseAuthentication no
      X11Forwarding no
      X11DisplayOffset 10
      PrintMotd no
      PrintLastLog yes
      ClientAliveInterval 60
      ClientAliveCountMax 10
      TCPKeepAlive yes
      AcceptEnv LANG LC_*
      Subsystem sftp /usr/lib/openssh/sftp-server
      UsePAM yes
      MaxAuthTries 3
      AllowAgentForwarding no
      AllowUsers kamal

runcmd:
  - apt-get remove -y --purge snapd snap
  - systemctl restart sshd
  - wget https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-amd64 -O /usr/local/bin/ctop
  - chmod +x /usr/local/bin/ctop

power_state:
  delay: "now"
  mode: reboot
  message: First reboot
  condition: True