FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    openssh-server sudo curl wget git vim nano \
    net-tools python3 python3-pip htop tmux \
    nginx gcc make unzip iputils-ping && apt clean

# Remove Docker giveaways
RUN rm -f /.dockerenv
RUN rm -rf /etc/docker 2>/dev/null || true

# Create users matching dart-prod-07
RUN useradd -m -s /bin/bash ubuntu && \
    useradd -m -s /bin/bash deploy && \
    useradd -m -s /bin/bash devops && \
    useradd -m -s /bin/bash jenkins

# Set passwords
RUN echo 'root:root' | chpasswd && \
    echo 'ubuntu:ubuntu' | chpasswd && \
    echo 'deploy:deploy123' | chpasswd

# Fake Uptime
RUN printf '#!/bin/bash\necho " 09:01:15 up 33 days,  2:17,  1 user,  load average: 0.23, 0.18, 0.12"\n' > /usr/local/bin/uptime
RUN chmod +x /usr/local/bin/uptime

# Fake Uptime v2
RUN echo '#!/bin/bash' > /usr/local/bin/cat && \
    echo 'if [[ "$*" == *"/proc/uptime"* ]]; then' >> /usr/local/bin/cat && \
    echo '    echo "2851200.00 11404800.00"' >> /usr/local/bin/cat && \
    echo 'elif [[ "$*" == *"--help"* ]]; then' >> /usr/local/bin/cat && \
    echo '    /bin/cat --help 2>&1 | sed "s|/bin/cat|cat|g"' >> /usr/local/bin/cat && \
    echo 'else' >> /usr/local/bin/cat && \
    echo '    /bin/cat "$@"' >> /usr/local/bin/cat && \
    echo 'fi' >> /usr/local/bin/cat
RUN chmod +x /usr/local/bin/cat

# Fake uname command with correct kernel version
RUN echo '#!/bin/bash' > /usr/local/bin/uname && \
    echo 'args="$*"' >> /usr/local/bin/uname && \
    echo 'if [[ "$args" == *"-a"* ]]; then' >> /usr/local/bin/uname && \
    echo '    echo "Linux dart-prod-07 6.17.0-1007-aws #7~24.04.1-Ubuntu SMP Thu Jan 22 21:04:49 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux"' >> /usr/local/bin/uname && \
    echo 'elif [[ "$args" == *"-s"* && "$args" == *"-n"* && "$args" == *"-m"* ]]; then' >> /usr/local/bin/uname && \
    echo '    echo "Linux dart-prod-07 6.17.0-1007-aws #7~24.04.1-Ubuntu SMP Thu Jan 22 21:04:49 UTC 2026 x86_64"' >> /usr/local/bin/uname && \
    echo 'elif [[ "$args" == *"-m"* ]]; then' >> /usr/local/bin/uname && \
    echo '    echo "x86_64"' >> /usr/local/bin/uname && \
    echo 'elif [[ "$args" == *"-r"* ]]; then' >> /usr/local/bin/uname && \
    echo '    echo "6.17.0-1007-aws"' >> /usr/local/bin/uname && \
    echo 'elif [[ "$args" == *"-n"* ]]; then' >> /usr/local/bin/uname && \
    echo '    echo "dart-prod-07"' >> /usr/local/bin/uname && \
    echo 'elif [[ "$args" == *"-s"* ]]; then' >> /usr/local/bin/uname && \
    echo '    echo "Linux"' >> /usr/local/bin/uname && \
    echo 'else' >> /usr/local/bin/uname && \
    echo '    echo "Linux"' >> /usr/local/bin/uname && \
    echo 'fi' >> /usr/local/bin/uname
RUN chmod +x /usr/local/bin/uname
# Match hostname to cowrie persona
RUN echo 'dart-prod-07' > /etc/hostname

# Match OS release to cowrie persona
RUN cat > /etc/os-release << 'OSEOF'
NAME="Ubuntu"
VERSION="22.04.3 LTS (Jammy Jellyfish)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 22.04.3 LTS"
VERSION_ID="22.04"
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
VERSION_CODENAME=jammy
UBUNTU_CODENAME=jammy
OSEOF

# Fake bash history
RUN echo -e 'cd /var/www/html\nls -la\nsystemctl status nginx\ntail -f /var/log/nginx/access.log\ngit pull origin main\nnano /etc/nginx/sites-available/default\nps aux\ndf -h\nfree -m' > /root/.bash_history

# Fake web root
RUN mkdir -p /var/www/html && \
    echo '<html><body>dart production</body></html>' > /var/www/html/index.html

# Fake apt history matching Feb 9 reboot date
RUN mkdir -p /var/log/apt && \
    printf "Start-Date: 2026-02-09  18:44:32\nCommandline: apt-get install nginx\nEnd-Date: 2026-02-09  18:44:51\n\nStart-Date: 2026-02-09  18:45:10\nCommandline: apt-get install python3-pip\nEnd-Date: 2026-02-09  18:45:32\n" > /var/log/apt/history.log

# Fake journal and log dirs
RUN mkdir -p /var/log/journal /run/systemd/private
RUN touch /var/log/lastlog /var/log/wtmp /var/log/btmp

# Realistic motd matching real kernel
RUN printf "\nWelcome to Ubuntu 22.04.3 LTS (GNU/Linux 6.17.0-1007-aws x86_64)\n\n * Documentation:  https://help.ubuntu.com\n * Management:     https://landscape.canonical.com\n * Support:        https://ubuntu.com/advantage\n\n" > /etc/motd

# Fake last command to hide Docker bridge IP and show realistic history
RUN printf '#!/bin/bash\necho "ubuntu   pts/0        10.0.0.2         Thu Mar 12 14:22   still logged in"\necho "ubuntu   pts/0        10.0.0.2         Wed Mar 11 09:15 - 17:43  (08:27)"\necho "deploy   pts/1        10.0.0.2         Tue Mar 10 11:02 - 11:45  (00:42)"\necho "ubuntu   pts/0        10.0.0.2         Mon Mar  9 08:30 - 18:11  (09:41)"\necho "reboot   system boot  6.17.0-1007-aws  Fri Feb  9 18:44   still running"\necho ""\necho "wtmp begins Fri Feb  9 18:44:01 2026"\n' > /usr/local/bin/last
RUN chmod +x /usr/local/bin/last

# SSH setup
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Generate SSH host keys at build time so they persist across restarts
RUN ssh-keygen -A

# Realistic environment
ENV HOME=/root
ENV TERM=xterm-256color
ENV SHELL=/bin/bash
ENV USER=root
ENV LOGNAME=root
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

EXPOSE 22

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]
