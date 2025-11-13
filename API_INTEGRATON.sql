CREATE OR REPLACE API INTEGRATION git_integration
   API_PROVIDER = git_https_api
   API_ALLOWED_PREFIXES = ('https://github.com/')
   API_USER_AUTHENTICATION = (
      TYPE = snowflake_github_app
   )
   ENABLED = TRUE;