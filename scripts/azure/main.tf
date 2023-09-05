provider "azurerm" {
  features {}
}

resource "tls_private_key" "admin-ssh-key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "azurerm_resource_group" "cle-rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_public_ip" "egress-pip" {
  name                = "egress-pip"
  location            = azurerm_resource_group.cle-rg.location
  resource_group_name = azurerm_resource_group.cle-rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "egress-lb" {
  name                = "egress-lb"
  location            = azurerm_resource_group.cle-rg.location
  resource_group_name = azurerm_resource_group.cle-rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "egress-lb-frontend-ip"
    public_ip_address_id = azurerm_public_ip.egress-pip.id
  }
}

resource "azurerm_lb_backend_address_pool" "egress-lb-pool" {
  name                = "egress-lb-pool"
  loadbalancer_id     = azurerm_lb.egress-lb.id
}

resource "azurerm_lb_probe" "egress-lb-probe" {
  name                = "egress-lb-probe"
  loadbalancer_id     = azurerm_lb.egress-lb.id
  protocol            = "Tcp"
  port                = 22
}

resource "azurerm_lb_rule" "egress-lb-rule" {
  name                           = "egress-lb-rule"
  protocol                       = "Tcp"
  frontend_port                  = 22
  backend_port                   = 22
  frontend_ip_configuration_name = "egress-lb-frontend-ip"
  loadbalancer_id                = azurerm_lb.egress-lb.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.egress-lb-pool.id]
  probe_id                       = azurerm_lb_probe.egress-lb-probe.id
  disable_outbound_snat          = true
}

resource "azurerm_lb_outbound_rule" "egress-lb-outbound-rule" {
  name                           = "egress-lb-outbound-rule"
  protocol                       = "All"
  loadbalancer_id                = azurerm_lb.egress-lb.id
  backend_address_pool_id        = azurerm_lb_backend_address_pool.egress-lb-pool.id
  enable_tcp_reset               = true
  frontend_ip_configuration {
    name                         = "egress-lb-frontend-ip"
  }
}

resource "azurerm_virtual_network" "client-vnet" {
  name                = "client-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.cle-rg.location
  resource_group_name = azurerm_resource_group.cle-rg.name
}

resource "azurerm_subnet" "client-subnet" {
  name                 = "client-subnet"
  resource_group_name  = azurerm_resource_group.cle-rg.name
  virtual_network_name = azurerm_virtual_network.client-vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_interface" "client-nic" {
  name                            = "client-nic"
  location                        = azurerm_resource_group.cle-rg.location
  resource_group_name             = azurerm_resource_group.cle-rg.name
  enable_accelerated_networking = true
  ip_configuration {
    name                          = "client-ipconfig"
    subnet_id                     = azurerm_subnet.client-subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_security_group" "client-nsg" {
  name                = "client-nsg"
  location            = azurerm_resource_group.cle-rg.location
  resource_group_name = azurerm_resource_group.cle-rg.name
}

resource "azurerm_network_security_rule" "client-nsr-ssh" {
  name                        = "client-nsr-ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.cle-rg.name
  network_security_group_name = azurerm_network_security_group.client-nsg.name
}

resource "azurerm_subnet_network_security_group_association" "client-subnet-nsg-association" {
  subnet_id                 = azurerm_subnet.client-subnet.id
  network_security_group_id = azurerm_network_security_group.client-nsg.id
}

resource "azurerm_network_interface_backend_address_pool_association" "client-nic-lb-egress-pool-association" {
  network_interface_id    = azurerm_network_interface.client-nic.id
  ip_configuration_name   = "client-ipconfig"
  backend_address_pool_id = azurerm_lb_backend_address_pool.egress-lb-pool.id
}

resource "azurerm_linux_virtual_machine" "client-vm" {
  name                            = "client-vm"
  resource_group_name             = azurerm_resource_group.cle-rg.name
  location                        = azurerm_resource_group.cle-rg.location
  size                            = "Standard_D2ds_v5"
  network_interface_ids           = [azurerm_network_interface.client-nic.id]

  admin_username = "adminuser"
  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.admin-ssh-key.public_key_openssh
  }
  disable_password_authentication = true

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}

resource "azurerm_public_ip" "ingress-pip" {
  name                = "ingress-pip"
  location            = azurerm_resource_group.cle-rg.location
  resource_group_name = azurerm_resource_group.cle-rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "ingress-lb" {
  name                = "ingress-lb"
  location            = azurerm_resource_group.cle-rg.location
  resource_group_name = azurerm_resource_group.cle-rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "ingress-lb-frontend-ip"
    public_ip_address_id = azurerm_public_ip.ingress-pip.id
  }
}

resource "azurerm_lb_backend_address_pool" "ingress-lb-pool" {
  name                = "ingress-lb-pool"
  loadbalancer_id     = azurerm_lb.ingress-lb.id
}

resource "azurerm_lb_probe" "ingress-lb-probe" {
  name                = "ingress-lb-probe"
  loadbalancer_id     = azurerm_lb.ingress-lb.id
  protocol            = "Http"
  port                = 8080
  request_path        = "/healthz"
}

resource "azurerm_lb_rule" "ingress-lb-rule" {
  name                           = "ingress-lb-rule"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 4443
  frontend_ip_configuration_name = "ingress-lb-frontend-ip"
  loadbalancer_id                = azurerm_lb.ingress-lb.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ingress-lb-pool.id]
  probe_id                       = azurerm_lb_probe.ingress-lb-probe.id
  enable_tcp_reset               = true
  disable_outbound_snat          = true
}

resource "azurerm_lb_outbound_rule" "ingress-lb-outbound-rule" {
  name                           = "ingress-lb-outbound-rule"
  protocol                       = "All"
  loadbalancer_id                = azurerm_lb.ingress-lb.id
  backend_address_pool_id        = azurerm_lb_backend_address_pool.ingress-lb-pool.id
  enable_tcp_reset               = true
  idle_timeout_in_minutes        = 66
  frontend_ip_configuration {
    name                         = "ingress-lb-frontend-ip"
  }
}

resource "azurerm_virtual_network" "server-vnet" {
  name                = "server-vnet"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.cle-rg.location
  resource_group_name = azurerm_resource_group.cle-rg.name
}

resource "azurerm_subnet" "server-subnet" {
  name                 = "server-subnet"
  resource_group_name  = azurerm_resource_group.cle-rg.name
  virtual_network_name = azurerm_virtual_network.server-vnet.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_network_security_group" "server-nsg" {
  name                = "server-nsg"
  location            = azurerm_resource_group.cle-rg.location
  resource_group_name = azurerm_resource_group.cle-rg.name
}

resource "azurerm_subnet_network_security_group_association" "subnet-nsg-association" {
  subnet_id                 = azurerm_subnet.server-subnet.id
  network_security_group_id = azurerm_network_security_group.server-nsg.id
}

resource "azurerm_network_security_rule" "server-nsr-ssh" {
  name                        = "server-nsr-ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.cle-rg.name
  network_security_group_name = azurerm_network_security_group.server-nsg.name
}

resource "azurerm_network_security_rule" "server-nsr-http" {
  name                        = "server-nsr-http"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.cle-rg.name
  network_security_group_name = azurerm_network_security_group.server-nsg.name
}

resource "azurerm_network_security_rule" "server-nsr-https" {
  name                        = "server-nsr-https"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "4443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.cle-rg.name
  network_security_group_name = azurerm_network_security_group.server-nsg.name
}

resource "azurerm_linux_virtual_machine_scale_set" "server-vmss" {
  name                            = "server-vmss"
  resource_group_name             = azurerm_resource_group.cle-rg.name
  location                        = azurerm_resource_group.cle-rg.location
  sku                            = "Standard_D2ds_v5"
  instances = 2

  admin_username = "adminuser"
  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.admin-ssh-key.public_key_openssh
  }
  disable_password_authentication = true

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "server-nic"
    primary = true
    enable_accelerated_networking = true

    ip_configuration {
      name      = "server-ipconfig"
      primary   = true
      subnet_id = azurerm_subnet.server-subnet.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.ingress-lb-pool.id]
    }
  }
}

resource "local_file" "ssh-private-key" {
  content  = tls_private_key.admin-ssh-key.private_key_pem
  filename = "${path.module}/private_key.pem"
  file_permission = "0600"
}