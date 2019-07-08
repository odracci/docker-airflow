#!/usr/bin/env bash

TRY_LOOP="20"

: "${MYSQL_HOST:="mysql"}"
: "${MYSQL_PORT:="3306"}"
: "${MYSQL_USER:="airflow"}"
: "${MYSQL_PASSWORD:="airflow"}"
: "${MYSQL_DB:="airflow"}"

# Defaults and back-compat
: "${AIRFLOW__CORE__FERNET_KEY:=${FERNET_KEY:=$(python -c "from cryptography.fernet import Fernet; FERNET_KEY = Fernet.generate_key().decode(); print(FERNET_KEY)")}}"
: "${SQL_ALCHEMY_CONN:=${SQL_ALCHEMY_CONN:-mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DB}}}"
: "${AIRFLOW__CORE__SQL_ALCHEMY_CONN:=${SQL_ALCHEMY_CONN}}"

export \
  AIRFLOW__CORE__FERNET_KEY \
  AIRFLOW__CORE__SQL_ALCHEMY_CONN \

# Install custom python package if requirements.txt is present
if [[ -e "/requirements.txt" ]]; then
    $(which pip) install --user -r /requirements.txt
fi

wait_for_port() {
  local name="$1" host="$2" port="$3"
  local j=0
  while ! nc -z "$host" "$port" >/dev/null 2>&1 < /dev/null; do
    j=$((j+1))
    if [[ $j -ge $TRY_LOOP ]]; then
      echo >&2 "$(date) - $host:$port still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for $name... $j/$TRY_LOOP"
    sleep 5
  done
}

if [[ "${WAIT_FOR_DATABASE:-0}" = "1" ]]; then
  wait_for_port "Mysql" "$MYSQL_HOST" "$MYSQL_PORT"
fi

if [[ "${CREATE_ADMIN_USER:-false}" = "true" ]]; then
    (airflow create_user -u airflow -l airflow -f jon -e airflow@apache.org -r Admin -p airflow || true)
fi

case "$1" in
  webserver)
    airflow initdb
    exec airflow webserver
    ;;
  worker|scheduler)
    # To give the webserver time to run initdb.
    exec airflow "$@"
    ;;
  flower)
    exec airflow "$@"
    ;;
  version)
    exec airflow "$@"
    ;;
  *)
    # The command is something like bash, not an airflow subcommand. Just run it in the right environment.
    exec "$@"
    ;;
esac
