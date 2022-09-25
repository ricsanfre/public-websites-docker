# Selfhosting personal static websites powered by private web analytics and private comments platform

This project shows how to configure a selfhosted server with internet access for selfhosting our static websites/blogs (for example created with [Jekyll](https://jekyllrb.com/) along with dynamic web services providing the capabilities to enable comments within our static sites and to track the number of visitors or the most viewed pages in our website.

This project enables to automatically deploy using Docker the following components:

  - [Traefik](traefik.io) as HTTP/HTTPS reverse proxy. Traefik is the front-end for all backend web services
  - [remark42](https://remark42.com/) as commenting platform for supporting comments in our posts
  - [matomo](https://matomo.org/) as web analytics platform for tracking visitors in our websites.
  - Personal static website, automatically generated with Jekyll and exposed by a static HTTP server like nginx or apache. As alternative personal websites can be hosted in third party static web hosting provider like Github Pages.

**Why Docker**

Docker, as container platform, enables the portability of the software between different hosting environments (bare metal, VM, etc.), so any kind of selfhosted platform can be used: a VM running on a Cloud Service Provider or a baremetal server with internet access like a Raspberry PI.

**Why Traefik**

For securing the access through HTTPS using SSL certificates, Traefik will be used.

Traefik is a Docker-aware reverse proxy with a monitoring dashboard. Traefik also handles setting up your SSL certificates using [Let’s Encrypt](https://letsencrypt.org/) allowing you to securely serve everything over HTTPS. Docker-aware means that Traefik is able to discover docker containers and using labels assigned to those containers automatically configure the routing and SSL certificates to each service. See Traefik documentation about [docker provider](https://doc.traefik.io/traefik/providers/docker/).

**Why Matomo**

Matomo is a selfhost alternative to Google Analytics service. It provides a better way to protect user's data privacy (user's data is not shared with any third party) and it can work in cookieless mode.

**Why remark42**

Remark is a seflhost alternative to other comments platforms (Disqus, Commento) that is free. It also provide a better way to protect user's data privacy and it enables social login (via Google, Twitter, Facebook, Microsoft, GitHub, Yandex, Patreon and Telegram) or post anonymous comments.

## Requirements

For selfhosting your websites you need:

- DNS domain owned by you. Different DNS subdomains need to be assigned to each of the published web services (matomo, remark42, personal website). Traefik rules will use the DNS domain information to route the HTTP/HTTPS traffic to the proper backend web service.
- Linux VM hosted in a Public Cloud Service Provider, with associated public IP address.
- Linux VM or baremetal server hosted by you in your home network. In this case you will use the Public IP address assigned by your ISP.

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

  ```shell
  pip3 install domain-connect-dyndns
  ```

- Step 2: Configure domain to be dynamically updated

  ```shell
  domain-connect-dyndns setup --domain <your-domain>
  ```

- Step 3: Update it
  
  ```shell
  domain-connect-dyndns update --all
  ```

## Docker configuration

### Installing docker and docker-compose

Docker and docker compose need to be installed on the server.
Ansible can be used to automatically deploy docker and docker compose on the server

### Create docker networks

Create a couple of docker network to interconnect all docker containers:

```shell
docker network create frontend
docker network create backend
```

Containers accesing to `frontend` network are the only ones that are exposing its ports to the host. Since the host will have internet acces, those exposed services will be accesible from Internet. Traefik container will be the only container to be attached to this network.

Containers accesing to `backend` network are not exposing any port to the server and so they are not accesible directly form internet. All backend containers will be attached to this network.

## Configuring and running Traefik with Docker


Traefik discovers automatically the routing configuration to be applied to each backend service, through the annotations specified in each of the backend containers (`labels` section in docker-compose file).

### Securing access to Docker API

For doing the automatic discovery of services, Traefik requires access to the docker socket to get its dynamic configuration. As Traefik official [documentation](https://doc.traefik.io/traefik/providers/docker/#docker-api-access) states, "Accessing the Docker API without any restriction is a security concern: If Traefik is attacked, then the attacker might get access to the underlying host".

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
      - backend
    ports:
      - 2375
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"

networks:
  backend:
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
      network: backend

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
  - Configure Docker as provider (`providers.docker`). Instead of using docker socket file, it uses as `endpoint` the Socket Proxy. Do not expose the containers by default (`exposedbydefault`), unless specified at container level with a label (`traefik.enable=true`), and use `backend` network as default for communicating with all containers.
  - Configure Traefik to automatically generate SSL certificates using Let's Encrypt (`certificatesResolvers`). ACME protocol is configured to use http challenge.

- Create empty `acme.json` file used to store SSL certificates generated by Traefik.

    touch acme.json
    chmod 600 acme.json

- Add Traefik service to docker-compose.yml file

```yml
services:
  traefik:
    depends_on:
      - dockerproxy
    image: traefik
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - frontend
    ports:
      - 80:80
      - 443:443
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./traefik/traefik.yml:/traefik.yml:ro
      - ./traefik/acme.json:/acme.json
```

### Annotating containers with Traefik rules

Traefik discovers automatically the routing configuration to be applied to each backend service, through the annotations specified in each of the backend containers (`labels` section in docker-compose file).

For example, to configure access to a backend service exposed at `myservice.domain.com` Traefik `router` rules must be specified to redirect the traffik to the proper container. Additionally routing modifiers (`middlewares`) can be used for redirecting HTTP to HTTPS traffic or to apply an authentication method.

For each backend service exposed through Traefik, a couple of `router` rules can be specified (one for handling HTTP traffic and another for handling HTTPS)

- Router for HTTP incoming traffic. Router rule name: will be the `<service_name>` where `service_name` is the associated service in the docker-compose file.
   
  - `traefik.http.routers.<service_name>.rule=Host(<service_domain>)`
  - `traefik.http.routers.<service_name>.entrypoint=http`
  - `traefik.http.routers.<service_name>.middlewares=<service_name>-https-redirect`
  - `traefik.http.middlewares.<service_name>-https-redirect.redirectscheme.scheme=https`

  Where <service_domain> specifies that the incoming traffic to that domain must be redirected to the container.

  And the configured `middleware` redirect all HTTP incoming traffic to the HTTPS entry point, and so to the HTTPS router rule.
   
- Router for HTTPS incoming traffic. Router rule name: will be `<service_name>-secure` 
  
  - `traefik.http.routers.<service_name>-secure.rule=Host(<service_domain>)`
  - `traefik.http.routers.<service_name>-secure.entrypoint=https`
  - `traefik.http.routers.<service_name>-secure.tls=true`: Enabling TLS certificates generation
  - `traefik.http.routers.<service_name>-secure>.tls.certresolver=http`: Issue the SSL certificate with the resolver specified in Traefik configuration (`traefik.yml`): Let's Encrypt (ACME protocol) with HTTP challenge.

- Additionally we need to tell Traefik which port of the container is being used.

  - `traefik.http.services.<service_name>.loadbalancer.server.port=<backend_port>`. Use container port <backend_port> to redirect all the traffic.
  
```yml
...
my_service:
  labels:
    # Explicitly tell Traefik to expose this container
    - "traefik.enable=true"
    # The domain the service will respond to
    - "traefik.http.routers.whoami.rule=Host(`whoami.domain.com`)"
    # Allow request only from the predefined entry point named "http"
    - "traefik.http.routers.whoami.entrypoints=http"
    # Redirect all incoming http traffic to HTTPS
    - "traefik.http.routers.whoami.middlewares=whoami-https-redirect"
    - "traefik.http.middlewares.whoami-https-redirect.redirectscheme.scheme=https"
    # Domain used for secure routing configuration
    - "traefik.http.routers.whoami-secure.rule=Host(`whoami.domain.com`)"
    # Allow requests in the predefined entry point "https"
    - `traefik.http.routers.whoami-secure.entrypoint=https`
    # Enabling TLS certificates generation
    - "traefik.http.routers.whoami-secure.tls=true"
    # Use SSL certificate resolver specified in configuration (Lets Encrypt)
    - "traefik.http.routers.whoami-secure.tls.certresolver=http`
```

### Configuring basic authentication access to Traefik dashboard

Traefik dashboard will be enabled. By default it does not provide any authentication mechanisms. Traefik HTTP basic authentication mechanims will be used.

In case that the backend does not provide authentication/authorization functionality, Traefik can be configured to provide HTTP authentication mechanism (basic authentication, digest and forward authentication).

Traefik's [Basic Auth Middleware](https://doc.traefik.io/traefik/middlewares/http/basicauth/) for providing basic auth HTTP authentication.

User:hashed-passwords pairs needed by the middleware can be generated with `htpasswd` utility. The command to execute is:

```shell
htpasswd -nb <user> <passwd>
```

`htpasswd` utility is part of `apache2-utils` package. In order to execute the command it can be installed with the command: `sudo apt install apache2-utils`

As an alternative, docker image can be used and the command to generate the user:hashed-password pairs is:
      
```shell
docker run --rm -it --entrypoint /usr/local/apache2/bin/htpasswd httpd:alpine -nb user password
```
For example:

```shell
htpasswd -nb admin secretpassword
admin:$apr1$3bVLXoBF$7rHNxHT2cLZLOr57lHBOv1
```

### Add Traefik service to docker-compose.yml file

```yml
services:
  traefik:
    depends_on:
      - dockerproxy
    image: traefik
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - frontend
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
  - Replace `monitor.yourdomain.com` in `traefik.http.routers.traefik.rule` and `traefik.http.routers.traefik-secure.rule` labels by your domain
  - Replace htpasswd pair generated before in `traefik.http.middlewares.traefik-auth.basicauth.users` label. 
    > NOTE: If te resulting string has any `$` you will need to modify them to be `$$` - this is because docker-compose uses `$` to signify a variable. By adding `$$` we still docker-compose that it’s actually a `$` in the string and not a variable.) 

This configuration will start Traefik service and enabling its dashboard at `monitor.yourdomain.com`. Enabling HTTPS, generating a TLS and  redirecting all HTTP traffic to HTTPS.

## Configuring and running web analytics service (Matomo) behind Traefik

Matomo service is composed of two containers: 
1) SQL database (MariaDB) 
2) Apache-based PHP website

- Step 1: Create matomo directories within User's home directory

    mkdir  ~/matomo
    mkdir -p ~/matomo/db
    mkdir -p ~/matomo/www-data

  `matomo/db` is a host directory to be used as docker bind mount for storing MariaDB's data
  `matomo/www-data` is a host directory to be used as docker bind mount for storing Matomo's website

- Step 2: Create environment file
 
  This file will contain environment variables for the two containers

  `~/matomo/db.env`
  ```
  MYSQL_ROOT_PASSWORD=<mysql_root_user_password>
  MYSQL_DATABASE=matomo
  MYSQL_USER=matomo
  MYSQL_PASSWORD=<matomo_user_password>
  MATOMO_DATABASE_ADAPTER=mysql
  MATOMO_DATABASE_TABLES_PREFIX=matomo_
  MATOMO_DATABASE_USERNAME=matomo
  MATOMO_DATABASE_PASSWORD=<matomo_user_password>
  MATOMO_DATABASE_DBNAME=matomo
  ```
  This environment files contains MariaDB root user credentials `MYSQL_ROOT_PASSWORD` and the database name (`matomo`) and the user (`matomo`) credentials to be used by Matomo.

- Step 3: Add MariaDB service to docker-compose.yml file

  ```yml
  db:
    image: mariadb
    container_name: mariadb
    networks:
      - backend
    command: --max-allowed-packet=64MB
    restart: always
    volumes:
      - ./matomo/db:/var/lib/mysql
    env_file:
      - ./matomo/db.env
  ```
  > NOTE: MariaDB container connected only to `backend` docker network. Host's matomo/db directory is mounted as MariaDB data base direcoty `/var/lib/mysql` 

- Step 4: Add annotated Matomo container to docker-compose.yml file

  ```yml
  matomo:
    depends_on:
      - db
    image: matomo
    container_name: matomo
    restart: always
    networks:
      - backend
    volumes:
      - ./matomo/www-data:/var/www/html
    environment:
      - MATOMO_DATABASE_HOST=db
    env_file:
      - ./matomo/db.env
    ports:
      - target: 80
        protocol: tcp
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.matomo.entrypoints=http"
      - "traefik.http.routers.matomo.rule=Host(`matomo.yourdomain.com`)"
      - "traefik.http.middlewares.matomo-https-redirect.redirectscheme.scheme=https"
      - "traefik.http.routers.matomo.middlewares=matomo-https-redirect"
      - "traefik.http.routers.matomo-secure.entrypoints=https"
      - "traefik.http.routers.matomo-secure.rule=Host(`matomo.yourdoamin.com`)"
      - "traefik.http.routers.matomo-secure.tls=true"
      - "traefik.http.routers.matomo-secure.tls.certresolver=http"
      - "traefik.http.routers.matomo-secure.service=matomo"
      - "traefik.http.services.matomo.loadbalancer.server.port=80"
  ```
  > NOTE: matomo container connected only to `backend` docker network. Host's matomo/www directory is mounted as Apaches's website directory `/var/www/html.
  >
  > Container annotated to be discovered by Traefik, exposing container tcp port 80, and creating the Traefik's rules to route the incoming traffic to Matomo's URL (`matomo.yourdomain.com`)

- Step 5: Finishing Matomo installation

  In order to finalize Matomo installation, Apache web server running on `matomo.yourdomain.com` need to be accesed and the procedure described in the [official documentation](https://matomo.org/docs/installation/) must be followed.

  For doing so you need to run the containers with the commad:

  ```shell
  docker-compose up -d
  ```

## Configuring and running comments platform (remark42) behind Traefik

- Step 1: Create remark42 directories within User's home directory

    mkdir  ~/remark42
    mkdir -p ~/remark42/var

  `remartk/var` is a host directory to be used as docker bind mount for storing remark42's data
  
- Step 2: Create environment file
 
  This file will contain environment variables for remark42 container

  `~/remark42/remark42.env`

  ```
  REMARK_URL=http://remark42.yourdoamin.com
  SECRET=<remark42_secret>
  STORE_BOLT_PATH=/srv/var/db
  BACKUP_PATH=/srv/var/backup
  SITE=<site_id>
  AUTH_ANON=true
  ```

  Where:
  - `site_id`: identifies the list of sites (`,` separated) which remark42 is storing the comments for.
    
    It must be the same `site_id` in the java script code added to your website. See [remark42 installation documentation](https://remark42.com/docs/getting-started/installation/)

  > NOTE: In this case only anonymous comments are being enabled. Other environment variables enables non-anonymous comments and integration of the authorization with external platforms Github, Google, etc.

- Step 3: Add annotated remark42 container to docker-compose.yml file

  ```yml
  ## Remark42
  remark42:
    image: umputun/remark42:latest
    container_name: "remark42"
    hostname: "remark42"
    restart: always
    networks:
      - backend
    volumes:
      - ./remark42/var:/srv/var
    ports:
      - target: 80
        protocol: tcp
    env_file:
      - ./remark42/remark42.env
    environment:
      - APP_UID=1000  # runs Remark42 app with non-default UID
      - TIME_ZONE=Europe/Madrid
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.remark42.entrypoints=http"
      - "traefik.http.routers.remark42.rule=Host(`remark42.yourdoamin.com`)"
      - "traefik.http.middlewares.remark42-https-redirect.redirectscheme.scheme=https"
      - "traefik.http.routers.remark42.middlewares=remark42-https-redirect"
      - "traefik.http.routers.remark42-secure.entrypoints=https"
      - "traefik.http.routers.remark42-secure.rule=Host(`remark42.yourdoamin.com`)"
      - "traefik.http.routers.remark42-secure.tls=true"
      - "traefik.http.routers.remark42-secure.tls.certresolver=http"
      - "traefik.http.routers.remark42-secure.service=remark42"
      - "traefik.http.services.remark42.loadbalancer.server.port=80"
      - "traefik.http.middlewares.remark42.headers.accesscontrolalloworiginlist=*"
  ```

  > NOTE: [Traefik middleware cors headers](https://doc.traefik.io/traefik/middlewares/http/headers/#cors-headers) must be used to avoid CORS issues with remark42.

    `traefik.http.middlewares.remark42.headers.accesscontrolalloworiginlist=*` to allow request from all orginins.

## Configuring and running your static website behind Traefik using Matomo and Remark42 services

Jekyll can be used for creating your static website. HTML templates need to be modified to include remark42 and matomo javascript code and remark42's html code.

### Creating your website with Jekyll

As a quick example:

- Step 1: Install jekyll (as prerequisite ruby package need to be installed)

  ```shell
  gem install bundler jekyll
  ```
- Step 2: Create a new jekyll site using default theme (`minima`)

  In $HOME directory execute
  ```shell
  jekyll new mywebsite
  ```

- Step 3: Create html code snippets containing matamo and remark java sctipt code

  This code snippets will be included in the HTML header of all the pages.

  Include matomo code snippet. This code from Matomo UI whenever a new site is added to be tracked.

  `_includes/matomo-analytics.html`
  ```html
  <!-- Matomo -->
  <script>
    var _paq = window._paq = window._paq || [];
    /* tracker methods like "setCustomDimension" should be called before "trackPageView" */
    _paq.push(['trackPageView']);
    _paq.push(['enableLinkTracking']);
    (function() {
      var u="//matomo.yourdomain.com/";
      _paq.push(['setTrackerUrl', u+'matomo.php']);
      _paq.push(['setSiteId', 'mywebsite']);
      var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0];
      g.async=true; g.src=u+'matomo.js'; s.parentNode.insertBefore(g,s);
    })();
  </script>
  <!-- End Matomo Code -->
  ```
  > NOTE: Here it is important to have the right URL for the matomo service  `matomo.yourdomain.com`  and the `site_id` identifying your website.

  Include remark42 code snippet. Code comes from [remark42 documentation](https://remark42.com/docs/configuration/frontend/) 

  `_includes/remark42.html`
  ```html
  <!-- Remark42 -->
  <script>
    var remark_config = {
      host: 'remark42.yourdomain.com',
      site_id: 'mywebsite',
      components: ['embed'], 
      theme: 'dark',
    };
  </script>
  <script>!function(e,n){for(var o=0;o<e.length;o++){var r=n.createElement("script"),c=".js",d=n.head||n.body;"noModule"in r?(r.type="module",c=".mjs"):r.async=!0,r.defer=!0,r.src=remark_config.host+"/web/"+e[o]+c,d.appendChild(r)}}(remark_config.components||["embed"],document);</script>
  <!-- End Remark42 Code -->
  ```
  
  > NOTE: Here it is important to set javascript variable `remark_config` containing the `host` where remark42 service is running (`remark42.yourdomain.com`) and the `site_id` identifying your website.

- Step 3: Modify header html code snippets to include remark42 and matomo javascript
  
  `_includes/head.html`
  ```html
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="{{ "/assets/main.css" | relative_url }}">
   
    {% if jekyll.environment == 'production' and site.matomo_analytics %}
      {% include matomo-analytics.html -%}
    {% endif %}
    {% if page.comments and jekyll.environment == 'production'%}
       {% include remark42.html %}
    {% endif %}
 
  </head>
  ```

- Step 4: Modify posts html layout to include remark42 comments

  `_layouts/post.html`

  ```html
  ....
  {% if page.comments and jekyll.environment == 'production' %}
  <div id="remark42"></div>
  {% endif %}
  ```

  > NOTE: matomo analytics ad remark42 snippet are only included in case the site is generated for production environment running the command
  > 
  > ```shell
  > JEKYLL_ENV=production bundle exec jekyll serve
  > ```
  >
  > Matomo analytics is only include if `matomo_analytics` is set to true in Jekylls' `_config.yml` file.
  > Remark42's comments are only enabled for those posts having the variable `comments` set to true 

- Step 5: Generate site HTML code executing the command

  ```shell
  JEKYLL_ENV=production bundle exec jekyll build
  ```

  HTML generated code is under `_site` directory

### How to deploy the static site in Docker
A simple Apache docker image (`httpd`) can be used and the complete static site generated by Jekyll (`_site` directory) can mounted in the docker container as bind mount of `/usr/local/apache2/htdocs`

- Step 1: Create mywebsite directories within User's home directory

    mkdir  ~/mywebsite
    mkdir -p ~/mywebsite/_site
 
- Step 2: Copy the Jekyll generated code of your website to `~/mywebsite/_site`

- Step 3: Add apache container server to `docker-compose.yml` file

  ```yml
  mywebsite:
    depends_on:
      - traefik
    image: httpd:2.4-alpine
    container_name: "mywebsite"
    hostname: "mywebsite"
    restart: always
    networks:
      - backend
    volumes:
      - ./mywebsite/_site:/usr/local/apache2/htdocs/
    ports:
      - target: 80
        protocol: tcp
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.mywebsite.entrypoints=http"
      - "traefik.http.routers.mywebsite.rule=Host(`$MYWEBSITE_URL`)"
      - "traefik.http.middlewares.mywebsite-https-redirect.redirectscheme.scheme=https"
      - "traefik.http.routers.mywebsite.middlewares=mywebsite-https-redirect"
      - "traefik.http.routers.mywebsite-secure.entrypoints=https"
      - "traefik.http.routers.mywebsite-secure.rule=Host(`$MYWEBSITE_URL`)"
      - "traefik.http.routers.mywebsite-secure.tls=true"
      - "traefik.http.routers.mywebsite-secure.tls.certresolver=http"
      - "traefik.http.routers.mywebsite-secure.service=mywebsite"
      - "traefik.http.services.mywebsite.loadbalancer.server.port=80"
  ```

  > NOTE: mywebsite container is running a basic apache image. Host's mywebsite/_site directory is mounted as Apaches's default html docs directory `/usr/local/apache2/htdocs/.
  > 
  > Container is annotated so it can be routed by Traefik.


## Backup

### Remark42 

Remark42 by default makes daily backup files in `~/remark42/var/backup`

This directory must be backed up daily

### Matomo

- Matomo website
  Backup `~/matomo/www-data` directory
- Matomo's MySQL database
  To perform Matomo's MySQl database backup use the provided script `matomo_mysql_backup.sh`

  This script exexutes a mysql dump command storing the result in compressed format in `~/matomo/backup/`
  This script must be executed daily and backup directory backed up daily.

### Backup documents references

- [Remark42 automatic and manual backup](https://remark42.com/docs/backup/backup/)
- [Matomo backup best practices](https://matomo.org/faq/on-premise/what-are-the-requirements-and-recommendations-for-matomo-backup/)
- [Matomo MySQL backup how to](https://matomo.org/faq/how-to/how-do-i-backup-and-restore-the-matomo-data/)

## Docker-compose commands to create/start/stop/upgrade the containers

All commands need to be executed in $HOME directory, where docker-compose.yml file is located

### Creating containers and starting the services

```shell
docker-compose up -d
```

### Stopping the containers

To stop all the services
```shell
docker-compose stop
```

To stop just one of the services

```shell
docker-compose stop <service_name>
```

### Starting the containers

To start all the services
```shell
docker-compose start
```

To start just one of the services

```shell
docker-compose start <service_name>
```

### Deleting the containers

```shell
docker-compose down
```
> NOTE: Since all data is stored in local host (using docker bind mounts), this command will not loose any important data.

### Check logs of one container

```shell
docker-compose logs -f <docker_service_name>
```

### Updating your docker images ##

This procedure indicates how to upgrade docker images of any of the services (matomo, remark42, etc.)

Updating with Docker Compose

1. Pull the new image from Docker Hub:

    ```shell
    docker-compose pull <docker_service_name>
    ```

1. Recreate the running container:

    ```shell
    docker-compose up --detach <docker_service_name>
    ```
