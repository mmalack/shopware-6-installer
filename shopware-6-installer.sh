#!/usr/bin/env bash

# exit script if a command exits with a non-zero
set -e

#############################################
#  Necessary functions for named arguments  #
#############################################

# https://keestalkstech.com/2022/03/named-arguments-in-a-bash-script/
# https://keestalkstech.com/2022/12/bash-script-with-a-lib-for-named-parameters/

function usage {
    echo ""
    echo -e "\033[32mInstalls Shopware 6 using production template and setup git and ddev.\033[m"
    echo ""
    echo -e "\033[32musage: $script_name --project_name string --branch string --env_file string\033[m"
    echo ""
    echo -e "\033[32m  --project_name string   name of the git repository where the project should be pushed to\033[m"
    echo -e "\033[32m                          (example: project-name)\033[m"
    echo -e "\033[32m  --branch string            branch or tag of the production template to be cloned\033[m"
    echo -e "\033[32m                          (example: v6.4.16.0)\033[m"
    echo -e "\033[32m  --env_file string          .env file containing necessary variables\033[m"
    echo -e "\033[32m                          (example: ./.env.project-name)\033[m"
    echo ""
}

# required parameter validation
function function_exists() {
    declare -f -F "$1" > /dev/null
    return $?
}

function die {
    printf "Script failed: %s\n\n" "$1"
    exit 1
}

function ensure_required_input_arg(){
    name=$1
    value=$2

    if [[ -z "$value" ]]; then
        function_exists usage && usage
        die "Missing parameter $name"
    fi
}


###################################
#  Initialize default parameters  #
###################################

# command name (does not handle symlinks)
script_name=`basename "$0"`
# command name (also handles symlinks)
#script_name="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
# default .env file (also handles symlinks)
env_file="$(dirname "$(test -L "$0" && readlink "$0" || echo "$0")")/.env.$script_name"


# parse all arguments and turn them into variables
while [ $# -gt 0 ]; do
    if [[ $1 == "--help" ]]; then
        usage
        exit 0
    elif [[ $1 == "--"* ]]; then
        v="${1/--/}"
        declare "$v"="$2"
        shift
    fi
    shift
done

ensure_required_input_arg "--project_name" "$project_name"


##################
#  Dependencies  #
##################

# first we need a .env file
if [ ! -f "$env_file" ]; then
  echo ".env file does not exist. Please create a file named ${env_file} or provide one via the parameter --env_file"
  exit 1
fi

# load .env file
set -a
# shellcheck disable=SC1090
[ -f "$env_file" ] && source "$env_file"
set +a

# check if ddev is installed
command -v ddev >/dev/null 2>&1 || { echo >&2 "ddev is required but not installed. Aborting..."; exit 1; }

# check if git is installed
command -v git >/dev/null 2>&1 || { echo >&2 "git is required but not installed. Aborting..."; exit 1; }

# check if git repo exists
git ls-remote $GIT_PRIVATE_URL/$project_name.git -q >/dev/null 2>&1 || { echo >&2 "git repository '$project_name' does not exist. Aborting..."; exit 1; }


########################
#  Start installation  #
########################

# clone the git repository
if [ ! -d "$project_name" ]; then
  git clone --branch=$GITHUB_BRANCH https://github.com/$GITHUB_PROJECT $project_name
fi

# cd into the project directory
cd $project_name

# Remove .git folder
rm -rf .git

# force add all files/folders from $GITHUB_PROJECT repository,
# because the gitignore is faulty and otherwise folders/files would be missing
git init --initial-branch=main
git add -f .

# configure ddev
ddev config --project-type=shopware6 --docroot=public --timezone=$TIMEZONE

# start ddev container
ddev start

# install shopware and dependencies according to the composer.lock
ddev composer install

# register shopware-packages repository
#ddev composer config repositories.shopware-packages '{"type": "composer", "url": "https://packages.shopware.com"}'
#if [ ! -z "$SW_PACKAGES_BEARER_TOKEN" ]; then
#  echo "save bearer token"
#  ddev composer config bearer.packages.shopware.com "$SW_PACKAGES_BEARER_TOKEN"
#fi

# setup the environment
#Options:
#  -f, --force                                                          Force setup and recreate everything
#      --no-check-db-connection                                         dont check db connection
#      --database-url[=DATABASE-URL]                                    Database dsn [default: "mysql://db:db@db:3306/db"]
#      --database-ssl-ca[=DATABASE-SSL-CA]                              Database SSL CA path [default: ""]
#      --database-ssl-cert[=DATABASE-SSL-CERT]                          Database SSL Cert path [default: ""]
#      --database-ssl-key[=DATABASE-SSL-KEY]                            Database SSL Key path [default: ""]
#      --database-ssl-dont-verify-cert[=DATABASE-SSL-DONT-VERIFY-CERT]  Database Don't verify server cert [default: ""]
#      --generate-jwt-keys                                              Generate jwt private and public key
#      --jwt-passphrase[=JWT-PASSPHRASE]                                JWT private key passphrase [default: "shopware"]
#      --composer-home=COMPOSER-HOME                                    Set the composer home directory otherwise the environment variable $COMPOSER_HOME will be used or the project dir as fallback [default: "/var/www/html/var/cache/composer"]
#      --app-env[=APP-ENV]                                              Application environment [default: "prod"]
#      --app-url[=APP-URL]                                              Application URL [default: "https://shopware6-test.ddev.site"]
#      --blue-green[=BLUE-GREEN]                                        Blue green deployment [default: "1"]
#      --es-enabled[=ES-ENABLED]                                        Elasticsearch enabled [default: "0"]
#      --es-hosts[=ES-HOSTS]                                            Elasticsearch Hosts [default: "elasticsearch:9200"]
#      --es-indexing-enabled[=ES-INDEXING-ENABLED]                      Elasticsearch Indexing enabled [default: "0"]
#      --es-index-prefix[=ES-INDEX-PREFIX]                              Elasticsearch Index prefix [default: "sw"]
#      --http-cache-enabled[=HTTP-CACHE-ENABLED]                        Http-Cache enabled [default: "1"]
#      --http-cache-ttl[=HTTP-CACHE-TTL]                                Http-Cache TTL [default: "7200"]
#      --cdn-strategy[=CDN-STRATEGY]                                    CDN Strategy [default: "id"]
#      --mailer-url[=MAILER-URL]                                        Mailer URL [default: "smtp://localhost:1025?encryption=&auth_mode="]
#      --dump-env                                                       Dump the generated .env file in a optimized .env.local.php file, to skip parsing of the .env file on each request
#  -h, --help                                                           Display help for the given command. When no command is given display help for the list command
#  -q, --quiet                                                          Do not output any message
#  -V, --version                                                        Display this application version
#      --ansi|--no-ansi                                                 Force (or disable --no-ansi) ANSI output
#  -n, --no-interaction                                                 Do not ask any interactive question
#  -e, --env=ENV                                                        The Environment name. [default: "prod"]

ddev exec bin/console system:setup \
  --quiet \
  --database-url=$DATABASE_URL \
  --app-env=$APP_ENV \
  --app-url=$APP_URL

# copy .env file for ddev
cp .env .env.ddev

# create database and install shopware
ddev exec bin/console system:install \
  --create-database \
  --shop-locale=$SHOP_LOCALE \
  --skip-jwt-keys-generation

# create an admin user
ddev exec bin/console user:create $USER_NAME --admin --email $USER_EMAIL --firstName $USER_FIRST_NAME --lastName $USER_LAST_NAME

# dump ddev database
ddev export-db --gzip=false > .ddev/dump.sql

# add the remaining files/folders to git
git add .

# commit files
git commit -m "Initial commit"

# add remote repository url
git remote add origin $GIT_PRIVATE_URL/$project_name.git

# add shopware production template as upstream
git remote add upstream https://github.com/$GITHUB_PROJECT.git

# push repository
#git push -u origin main
git push --force -u origin main

# Launch the administration in browser
ddev launch /admin