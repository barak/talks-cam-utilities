# encoding: utf-8
#
# This is a model definition for Backup v3 http://meskyanichi.github.io/backup/v3/
# Its purpose is to push the contents of the talks.cam MySQL database
# to Sparrho (http://www.sparrho.com/) to enable them to present
# talks.cam data. Talk to John/Nico for an explanation of why this is
# happening.
#
# Set the TALKS_DB_YML_PATH envar to the path to the talks database.yml
# config file to pull the db credentials from the production db conf.
#
# WARNING: The talks db unfortunately contains plaintext passwords.
# Great care must be taken to not leak this information. This is
# currently achieved by excluding the users table (which contains the
# password column). Another table - 'clean_users' is created before each
# backup. It contains the users table without the passwords column.
#

require "dbi"
require "yaml"

SQL_DELETE_CLEAN_USERS = "DELETE FROM clean_users;"
SQL_CREATE_CLEAN_USERS = "CREATE TABLE IF NOT EXISTS clean_users (id int(11), email varchar(255), name varchar(255), affiliation varchar(75), administrator int(50), old_id int(11), last_login datetime, crsid varchar(255), image_id int(11), name_in_sort_order varchar(255), ex_directory tinyint(1), created_at time, updated_at time);"
SQL_POPULATE_CLEAN_USERS = "INSERT INTO clean_users SELECT id, email, name, affiliation, administrator, old_id, last_login, crsid, image_id, name_in_sort_order, ex_directory, created_at, updated_at FROM users;"

def get_db_params
  path = ENV["TALKS_DB_YML_PATH"] || "/some/where/database.yml"
  file = File.open(path)
  conf = YAML.load(file)

  conf["production"]
end

db_params = get_db_params
db_name = db_params["database"]
db_host = db_params["host"]
db_username = db_params["username"]
db_password = db_params["password"]

Model.new(:talks_mysql, 'Talks MySQL Sparrho') do
  before do

    # Create the clean_users table if it doesn't yet exist, then sync it
    # with the users table before running our backup.
    # Same example, but a little more Ruby-ish
    DBI.connect("DBI:Mysql:#{db_name}:#{db_host}", db_username, db_password) do | dbh |
        dbh.do(SQL_CREATE_CLEAN_USERS)
        dbh.do(SQL_DELETE_CLEAN_USERS)
        dbh.do(SQL_POPULATE_CLEAN_USERS)
    end
  end

  database MySQL do |db|
    db.name               = db_name
    db.username           = db_username
    db.password           = db_password
    db.host               = db_host

    db.skip_tables        = ["users"]
    db.only_tables        = [
      "custom_views",
      "document_versions",
      "documents",
      "email_subscriptions",
      "images",
      "list_lists",
      "list_talks",
      "list_users",
      "lists",
      "related_lists",
      "related_talks",
      "schema_info",
      "sessions",
      "talks",
      "tickles",
      "clean_users"
    ]
    db.additional_options = ["--quick", "--single-transaction", "--compatible=postgresql"]
  end

  ##
  # Local (Copy) [Storage]
  #
  store_with Local do |local|
    local.path       = "~/backups/"
    local.keep       = 5
  end

  ##
  # Gzip [Compressor]
  #
  compress_with Gzip

  # Push the backup to Sparrho's S3 bucket:
  # store_with S3 do |s3|
  #   # AWS Credentials
  #   s3.access_key_id     = "AKIAICTSOX2ZZ3IKY7LQ"
  #   s3.secret_access_key = "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"
  #   # Or, to use a IAM Profile:
  #   # s3.use_iam_profile = true

  #   s3.region             = 'us-east-1'
  #   s3.bucket             = 'sparrho-static'
  #   s3.path               = '/DUMPS/talks.cam'
  # end

  # POST to an endpoint provided by Sparrho when the backup has been performed.
  # notify_by HttpPost do |post|
  #   post.on_success = true
  #   post.on_warning = true
  #   post.on_failure = false

  #   # URI to post the notification to.
  #   # Port may be specified if needed.
  #   # If Basic Authentication is required, supply user:pass.
  #   post.uri = 'http://fierce-fjord-3584.herokuapp.com/_update/sync/talks-cam/'
  # end
end
