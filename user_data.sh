#!/bin/bash
set -euxo pipefail

apt-get update
apt-get install -y nginx

TOKEN=$(curl -sS -X PUT \
  "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -sS \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -sS \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /var/www/html/index.nginx-debian.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Multi-AZ Nginx Application</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      max-width: 700px;
      margin: 80px auto;
      padding: 24px;
      background: #f4f7fb;
      color: #172b4d;
    }
    main {
      background: white;
      padding: 32px;
      border-radius: 12px;
      box-shadow: 0 4px 18px #0001;
    }
    h1 { color: #1463c5; }
  </style>
</head>
<body>
  <main>
    <h1>Multi-AZ High Availability Project</h1>
    <p>Nginx is running successfully on AWS EC2.</p>
    <p><strong>Instance ID:</strong> ${INSTANCE_ID}</p>
    <p><strong>Availability Zone:</strong> ${AZ}</p>
    <p>Served through an Application Load Balancer.</p>
  </main>
</body>
</html>
EOF

systemctl enable nginx
systemctl restart nginx
