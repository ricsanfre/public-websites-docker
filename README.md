# Publishing secured websites with Traefik and Let's encrypt using docker-compose

How to configure a selfhosted server with internet access for publishig our websites using docker and Traefik as HTTP/HTTPS reverse Proxy.

Docker, as container platform, enables the portability of the software between different hosting environments (bare metal, VM, etc.), so any kind of selfhosted platform can be used: a VM running on a Cloud Service Provider or a baremetal server with internet access like a Raspberry PI.

For securing the access through HTTPS using SSL certificates, Traefik will be used.

Traefik is a Docker-aware reverse proxy with a monitoring dashboard. Traefik also handles setting up your SSL certificates using Let’s Encrypt allowing you to securely serve everything over HTTPS. Docker-aware means that Traefik is able to discover docker containers and using labels assigned to those containers automatically configure the routing and SSL certificates to each service. See Traefik documentation about [docker provider](https://doc.traefik.io/traefik/providers/docker/) 

## Enabling Internet Access

Traefik front end need to be accesible from the Internet. Incoming HTTP/HTTPS (tcp ports 80 and 443) traffic need to be enabled and so the server.

### Using Cloud Service Provider

In case of using a Cloud Service Provided, the IP address assigned to the VM for hosting the websites need to be created wih an external IP (public IP address) and the corresponding security rules (i.e.: security groups) need to be configured to enable the incoming HTTP/HTTPS traffic.

### Selfhosting at home network

At home usually the ISP provide a public IP address to your home router (GPON or ADSL router) and the router provide internet access to your home network via NAT. Incoming traffic on HTTP/HTTPS ports for your home network is usually blocked by the home router. 

Home router port forwarding must be enabled in order to reach a host in your home network from Internet.
Traffic incoming to ports 80 (HTTP) and 443 (HTTPS) will be redirected to the IP address of the server at your home network hosting the websites.

Enable port forwarding for TCP ports 80/443 to `server_ip` (IP from your home network) associated to the server at home network.

| WAN Port | LAN IP | LAN Port |
|----------|--------|----------|
| 80 | `server_ip` | 80 |
| 443 | `server_ip`| 443 |

### Configure OS level Firewall

Configure local firewall at OS level to enable the incoming traffic on ports 80 and 443

For example: in case of Ubuntu OS, Ubuntu's embedded firewall (ufw) need to be configured, allowing only incoming SSH, HTTP and HTTPS traffic.
  ```
  sudo ufw allow 22
  sudo ufw allow 80
  sudo ufw allow 443
  sudo ufw enable
  ```

If the OS is configured with Iptables rules by default (i.e.: Oracle Cloud Ubuntu's VM are created with ufw disabled but wiht Iptables configured), Iptables rules need to be added to enable the incoming traffic
```
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --match multiport --dports 80,443 -j ACCEPT
sudo netfilter-persistent save
```

## DNS configuration

Using your DNS provider, add the DNS records of the webservices you want to publish pointing to the public IP address of the server. 

In case of using a Cloud Service Provided, the IP address assigned to the VM created. VM need to be created with a external IP (public IP address).

In case of hosting at home the IP address assigned by your ISP (public IP address of your home network)

In case of ISP is using dynmaic IP public addresses, Dynamic DNS must be configured to keep up to date the DNS records mapped to the assigned public IP addresses


### Configure Dynamic DNS (Selfhosting at home)

In case that your ISP only provide you dynamic IP address, IP address associated to DNS records need to be dynamically updated. Most DNS providers supports DynDNS with an open protocol [Domain Connect](https://www.domainconnect.org/) enabling the automatic DNS update ousing the IP public address assigned by the ISP.
For example IONOS DNS provider provides the following [instructions](https://www.ionos.com/help/domains/configuring-your-ip-address/connecting-a-domain-to-a-network-with-a-changing-ip-using-dynamic-dns-linux/) to configure DynDNS

- Step 1: Install python package

    pip3 install domain-connect-dyndns

- Step 2: Configure domain to be dynamically updated

    domain-connect-dyndns setup --domain ricsanfre.com

- Step 3: Update it

    domain-connect-dyndns update --all


## Docker configuration

### Installing docker and docker-compose

Docker and docker compose need to be installed on the server.
Ansible can be used to automatically deploy docker and docker compose on the server


### Create docker networks

Create a couple of docker network to interconnect all docker containers

  docker network create dmz
  docker network create internal

containers accesing to `dmz` network are the only ones that are publishing ports on the hosted server. Since the host will have internet acces, those services will be accesible from Internet.
containers accesing to `internal` network are not publishing any port on the hosted server and so they are not accesible directly form internet.

## Configuring and running Traefik with Docker

### Securing access to Docker API

Traefik discovers automatically the configuration to be applied to docker containers, specified in labels. 
For doing that Traefik requires access to the docker socket to get its dynamic configuration. As Traefik official [documentation](https://doc.traefik.io/traefik/providers/docker/#docker-api-access) states, "Accessing the Docker API without any restriction is a security concern: If Traefik is attacked, then the attacker might get access to the underlying host".

There are several mechanisms to secure the access to Docker API, one of them is the use of a docker proxy like the one provided by Tecnativa, [Tecnativa's Docker Socket Proxy](https://github.com/Tecnativa/docker-socket-proxy). Instead of allowing our publicly-facing Traefik container full access to the Docker socket file, we can instead proxy only the API calls we need with Tecnativa’s Docker Socket Proxy project. This ensures Docker’s socket file is never exposed to the public along with all the headaches doing so could cause an unknowing site owner.

Setting up Docker Socket Proxy. In the home directory create initial `docker-compose.yaml` file

```yml
version: "3.8"

services:
  dockerproxy:
    container_name: docker-proxy
    environment:
      CONTAINERS: 1
    image: tecnativa/docker-socket-proxy
    networks:
      - web
    ports:
      - 2375
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"

networks:
  web:
    external: true

```

### Create folders and basic traefik configuration

- Step create traefik directory within User's home directory

   mkdir  ~/traefik

- Create Traefik configuration file `traefik.yml`

  ```yml
  api:
    dashboard: true
    debug: false

  entryPoints:
    http:
      address: ":80"
    https:
      address: ":443"

  providers:
    docker:
      endpoint: "tcp://docker-proxy:2375"
      watch: true
      exposedbydefault: false

  certificatesResolvers:
    http:
      acme:
        email: admin@ricsanfre.com
        storage: acme.json
        httpChallenge:
          entryPoint: http

  ```
  This configuration file:

  - Enables Traefik dashoard (`api.dashboard`= true)
  - Configure Traefik HTTP and HTTPS default ports as entry points (`entryPoints`)
  - Configure Docker as provider (`providers.docker`). Instead of using docker socket file, it uses as endpoint the Socket Proxy
  - Configure Traefik to automatically generate SSL certificates using Let's Encrypt. ACME protocol is configured to use http challenge.

- Create empty `acme.json` file used to store SSL certificates generated by Traefik.

    touch acme.json
    chmod 600 acme.json

### Configuring basic authentication access to Traefik dashboard
Traefik dashboard will be enabled. By default it does not provide any authentication mechanisms. Traefik HTTP basic authentication mechanims will be used.

In case that the backend does not provide authentication/authorization functionality, Traefik can be configured to provide HTTP authentication mechanism (basic authentication, digest and forward authentication).

Traefik's [Basic Auth Middleware](https://doc.traefik.io/traefik/middlewares/http/basicauth/) for providing basic auth HTTP authentication.

User:hashed-passwords pairs needed by the middleware can be generated with `htpasswd` utility. The command to execute is:

    htpasswd -nb <user> <passwd>

`htpasswd` utility is part of `apache2-utils` package. In order to execute the command it can be installed with the command: `sudo apt install apache2-utils`

As an alternative, docker image can be used and the command to generate the user:hashed-password pairs is:
      
```  
docker run --rm -it --entrypoint /usr/local/apache2/bin/htpasswd httpd:alpine -nb user password
```
For example:
 
  htpasswd -nb admin secretpassword
  admin:$apr1$3bVLXoBF$7rHNxHT2cLZLOr57lHBOv1


### Add Traefik service to docker-compose.yml file


```yml
services:
  traefik:
    depends_on:
      - dockerproxy
    image: traefik:v2.0
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - web
    ports:
      - 80:80
      - 443:443
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./traefik/traefik.yml:/traefik.yml:ro
      - ./traefik/acme.json:/acme.json
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.entrypoints=http"
      - "traefik.http.routers.traefik.rule=Host(`monitor.yourdomain.com`)"
      - "traefik.http.middlewares.traefik-auth.basicauth.users=admin:$$apr1$$3bVLXoBF$$7rHNxHT2cLZLOr57lHBOv1"
      - "traefik.http.middlewares.traefik-https-redirect.redirectscheme.scheme=https"
      - "traefik.http.routers.traefik.middlewares=traefik-https-redirect"
      - "traefik.http.routers.traefik-secure.entrypoints=https"
      - "traefik.http.routers.traefik-secure.rule=Host(`monitor.yourdomain.com`)"
      - "traefik.http.routers.traefik-secure.middlewares=traefik-auth"
      - "traefik.http.routers.traefik-secure.tls=true"
      - "traefik.http.routers.traefik-secure.tls.certresolver=http"
      - "traefik.http.routers.traefik-secure.service=api@internal"
```

Where:
  - Replace `monitor.yourdomain.com` in `traefik.http.routers.traefik.rule` `traefik.http.routers.traefik-secure.rule` labels by your domain
  - Replace htpasswd pair generated before in `traefik.http.middlewares.traefik-auth.basicauth.users` label. (NOTE: If te resulting string has any $ you will need to modify them to be $$ - this is because docker-compose uses $ to signify a variable. By adding $$ we still docker-compose that it’s actually a $ in the string and not a variable.) 

This configuration will start Traefik service and enabling its dashboard at `monitor.yourdomain.com`. Enabling HTTPS, generating a TLS  and  redirecting all HTTP traffic to HTTPS.


## Configuring and running a public webservice (Example Foundry VTT)


### Create folders and basic Foundry VTT configuration files

- Step 1 create foundry directory within User's home directory

    mkdir ~/foundry

- Step 2 create data directory where all Foundry VTT and database will be stored
    mkdir ~/foundry/data

- Step 3: Create a container_cache directory where Foundry VTT binaries will be stored

    mkdir ~/foundry/data/container_cache

### Create foundry user

Foundry VTT docker image runs as not privileged user (`foundry`) and container automatically change the owner of the `data` directory (docker bind mount)

The same user should exits in the host, in order to show properly the permisions of the files. Check [Dockerfile](https://raw.githubusercontent.com/felddy/foundryvtt-docker/develop/Dockerfile) to see which is the internal user configured

    sudo groupadd --system -g 421 foundry
    sudo useradd --system --uid 421 --gid foundry foundry



### Create docker secrets file to store Foundry VTT credentials and license key

- Create file `~/foundry/secrets.json`

  ```json
  {
  "foundry_admin_key": "foundry-admin-password",
  "foundry_password": "password",
  "foundry_username": "user",
  "foundry_license_key": "foundry-license-key"
  }
  ```

  This will be used by docker image to automatically download the software, configure admin password and installing the license key.

### Add Foundry VTT to docker compose


```yml
secrets:
  config_json:
    file: ~/foundry/secrets.json

  foundryvtt:
    depends_on:
      - traefik
    container_name: foundryvtt
    image: felddy/foundryvtt:release
    hostname: dndtools
    networks:
      - web
    init: true
    restart: "unless-stopped"
    volumes:
      - type: bind
        source: ~/foundry/data
        target: /data
    environment:
      - CONTAINER_CACHE=/data/container_cache
      - CONTAINER_PATCHES=/data/container_patches
      - CONTAINER_PRESERVE_OWNER=/data/Data/my_assets
      - FOUNDRY_PROXY_SSL=true
    ports:
      - target: 30000
        protocol: tcp
    secrets:
      - source: config_json
        target: config.json
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=dmz"
      - "traefik.http.routers.foundryvtt.entrypoints=http"
      - "traefik.http.routers.foundryvtt.rule=Host(`foundry.ricsanfre.com`)"
      - "traefik.http.middlewares.foundryvtt-https-redirect.redirectscheme.scheme=https"
      - "traefik.http.routers.foundryvtt.middlewares=foundryvtt-https-redirect"
      - "traefik.http.routers.foundryvtt-secure.entrypoints=https"
      - "traefik.http.routers.foundryvtt-secure.rule=Host(`foundry.ricsanfre.com`)"
      - "traefik.http.routers.fouundryvtt-secure.tls=true"
      - "traefik.http.routers.foundryvtt-secure.tls.certresolver=http"
      - "traefik.http.routers.foundryvtt-secure.service=foundryvtt"
      - "traefik.http.services.foundryvtt.loadbalancer.server.port=30000"

```

Docker image is started using two environment variables:

- `CONTAINER_CACHE=/data/container_cache`: To use a cache for storing installation files instead of download it every time the container is booted
- `FOUNDRY_PROXY_SSL=true`: to indicate that FoundryVTT is running behind a reverse proxy that uses SSL (Traefik). This allows invitation links and A/V functionality to work as if the Foundry Server had SSL configured directly.

- `CONTAINER_PATCHES=/data/container_patches`: path to list of scripts that docker image executes after instalallation before starting the application.
- `CONTAINER_PRESERVE_OWNER=/data/Data/my_assets`: Avoid changing of permissions of the assets folders


