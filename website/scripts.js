const config = window.APP_CONFIG;

const redirectUri = window.location.origin;

function login() {

    const loginUrl =
        `https://${config.COGNITO_DOMAIN}.auth.${config.REGION}.amazoncognito.com/login` +
        `?client_id=${config.CLIENT_ID}` +
        `&response_type=code` +
        `&scope=openid+email+profile` +
        `&redirect_uri=${encodeURIComponent(redirectUri)}`;

    window.location.href = loginUrl;
}

function logout() {

    const logoutUrl =
        `https://${config.COGNITO_DOMAIN}.auth.${config.REGION}.amazoncognito.com/logout` +
        `?client_id=${config.CLIENT_ID}` +
        `&logout_uri=${encodeURIComponent(redirectUri)}`;

    window.location.href = logoutUrl;
}

function getCode() {

    const params = new URLSearchParams(
        window.location.search
    );

    return params.get("code");
}

async function exchangeCodeForTokens(code) {

    const tokenEndpoint =
        `https://${config.COGNITO_DOMAIN}.auth.${config.REGION}.amazoncognito.com/oauth2/token`;

    const body =
        `grant_type=authorization_code` +
        `&client_id=${config.CLIENT_ID}` +
        `&code=${code}` +
        `&redirect_uri=${encodeURIComponent(redirectUri)}`;

    const response = await fetch(
        tokenEndpoint,
        {
            method: "POST",

            headers: {
                "Content-Type":
                    "application/x-www-form-urlencoded"
            },

            body
        }
    );

    const tokens = await response.json();

    localStorage.setItem(
        "access_token",
        tokens.access_token
    );

    localStorage.setItem(
        "id_token",
        tokens.id_token
    );

    localStorage.setItem(
        "refresh_token",
        tokens.refresh_token
    );

    document.getElementById("output").textContent =
        JSON.stringify(tokens, null, 2);
}

function showToken() {

    document.getElementById("output").textContent =
        localStorage.getItem("access_token");
}

window.addEventListener(
    "load",
    async () => {

        const code = getCode();

        if (code) {

            await exchangeCodeForTokens(code);

            window.history.replaceState(
                {},
                document.title,
                "/"
            );
        }
    }
);