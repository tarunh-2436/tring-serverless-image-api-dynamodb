def lambda_handler(event, context):

    event["response"]["claimsAndScopeOverrideDetails"] = {
        "idTokenGeneration": {"claimsToAddOrOverride": {"userType": "AUTHENTICATED"}},
        "accessTokenGeneration": {
            "claimsToAddOrOverride": {"userType": "AUTHENTICATED"}
        },
    }

    return event
