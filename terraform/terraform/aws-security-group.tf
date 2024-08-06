resource "aws_security_group" "<YOUR-LOCAL-NAME>" { #This name I need to use below and ADD .id in last
  name        = "First-instance-with-terraform"
  description = "Managed from Terraform"
}

#Inbound rules
resource "aws_vpc_security_group_ingress_rule" "http_for_all" {
  security_group_id = aws_security_group.<YOUR-LOCAL-NAME>.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}


#Inbound rules
resource "aws_vpc_security_group_ingress_rule" "https_for_all" {
  security_group_id = aws_security_group.<YOUR-LOCAL-NAME>.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
  description       = "Allow all traffic for HTTPS"
}

#Inbound rules
resource "aws_vpc_security_group_ingress_rule" "ssh_with_my_ip" {
  security_group_id = aws_security_group.<YOUR-LOCAL-NAME>.id
  cidr_ipv4         = "103.249.234.117/32"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
  description       = "Allow SSH from my IP"
}


#Outbound rules
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.<YOUR-LOCAL-NAME>.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" #Here -1 mean allow all traffic 
}
