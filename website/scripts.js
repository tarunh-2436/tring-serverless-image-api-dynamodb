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
  localStorage.removeItem("access_token");

  localStorage.removeItem("id_token");

  localStorage.removeItem("refresh_token");

  const tableBody = document.getElementById("imagesTableBody");

  if (tableBody) {
    tableBody.innerHTML = "";
  }

  const status = document.getElementById("uploadStatus");

  if (status) {
    status.textContent = "";
  }

  updateLoginStatus();

  const logoutUrl =
    `https://${config.COGNITO_DOMAIN}.auth.${config.REGION}.amazoncognito.com/logout` +
    `?client_id=${config.CLIENT_ID}` +
    `&logout_uri=${encodeURIComponent(redirectUri)}`;

  window.location.href = logoutUrl;
}

function getCode() {
  const params = new URLSearchParams(window.location.search);

  return params.get("code");
}

function getAccessToken() {
  return localStorage.getItem("access_token");
}

function updateLoginStatus() {
  const status = document.getElementById("loginStatus");

  if (!status) {
    return;
  }

  const token = getAccessToken();

  if (token) {
    status.textContent = "🟢 Logged In";
  } else {
    status.textContent = "🔴 Logged Out";
  }
}

async function exchangeCodeForTokens(code) {
  const tokenEndpoint = `https://${config.COGNITO_DOMAIN}.auth.${config.REGION}.amazoncognito.com/oauth2/token`;

  const body =
    `grant_type=authorization_code` +
    `&client_id=${config.CLIENT_ID}` +
    `&code=${code}` +
    `&redirect_uri=${encodeURIComponent(redirectUri)}`;

  const response = await fetch(tokenEndpoint, {
    method: "POST",

    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },

    body,
  });

  const tokens = await response.json();

  localStorage.setItem("access_token", tokens.access_token);

  localStorage.setItem("id_token", tokens.id_token);

  localStorage.setItem("refresh_token", tokens.refresh_token);

  updateLoginStatus();
}

async function uploadImage() {
  const file = document.getElementById("imageFile").files[0];

  if (!file) {
    alert("Please select an image");

    return;
  }

  const uploadStatus = document.getElementById("uploadStatus");

  try {
    uploadStatus.textContent = "Creating upload request...";

    const token = getAccessToken();

    if (!token) {
      uploadStatus.textContent = "Please login first";

      return;
    }

    const createResponse = await fetch(`${config.API_URL}/dev/images`, {
      method: "POST",

      headers: {
        "Content-Type": "application/json",

        Authorization: `Bearer ${token}`,
      },

      body: JSON.stringify({
        filename: file.name,
        contentType: file.type,
      }),
    });

    if (!createResponse.ok) {
      throw new Error("Failed to create upload");
    }

    const createData = await createResponse.json();

    uploadStatus.textContent = "Uploading image...";

    const uploadResponse = await fetch(createData.uploadUrl, {
      method: "PUT",

      headers: {
        "Content-Type": file.type,
      },

      body: file,
    });

    if (!uploadResponse.ok) {
      throw new Error("Upload failed");
    }

    uploadStatus.textContent = "Upload successful";

    setTimeout(loadImages, 2000);
  } catch (error) {
    console.error(error);

    uploadStatus.textContent = error.message;
  }
}

async function loadImages() {
  try {
    const token = getAccessToken();

    const tbody = document.getElementById("imagesTableBody");

    if (!token) {
      if (tbody) {
        tbody.innerHTML = "";
      }

      return;
    }

    const response = await fetch(`${config.API_URL}/dev/images`, {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    if (!response.ok) {
      throw new Error("Failed to load images");
    }

    const data = await response.json();

    tbody.innerHTML = "";

    data.images.forEach((image) => {
      tbody.innerHTML += `
                    <tr>
                        <td>${image.filename}</td>

                        <td>
                            ${image.status}
                        </td>

                        <td>
                            ${new Date(image.createdAt).toLocaleString()}
                        </td>

                        <td>
                            <button
                                onclick="viewImage('${image.imageId}')">
                                View
                            </button>
                        </td>
                    </tr>
                `;
    });
  } catch (error) {
    console.error(error);
  }
}

async function viewImage(imageId) {
  try {
    const token = getAccessToken();

    const response = await fetch(`${config.API_URL}/dev/images/${imageId}`, {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    if (!response.ok) {
      throw new Error("Failed to load image");
    }

    const data = await response.json();

    const image = data.image;

    document.getElementById("imageDetails").innerHTML = `

            <img
                src="${data.downloadUrl}"
                alt="${image.filename}"
                class="modal-image">

            <p>
                <strong>Filename:</strong>
                ${image.filename}
            </p>

            <p>
                <strong>Status:</strong>
                ${image.status}
            </p>

            <p>
                <strong>File Size:</strong>
                ${image.fileSize} bytes
            </p>

            <p>
                <strong>Content Type:</strong>
                ${image.contentType}
            </p>

            <p>
                <strong>Extension:</strong>
                ${image.extension}
            </p>

            <p>
                <strong>Created At:</strong>
                ${image.createdAt}
            </p>

            <p>
                <strong>Processed At:</strong>
                ${image.processedAt || "N/A"}
            </p>

            <p>
                <strong>Image ID:</strong>
                ${image.imageId}
            </p>
        `;

    document.getElementById("imageModal").classList.remove("hidden");
  } catch (error) {
    console.error(error);
  }
}

function closeModal() {
  document.getElementById("imageModal").classList.add("hidden");
}

document.getElementById("imageFile")?.addEventListener("change", (event) => {
  const file = event.target.files[0];

  const preview = document.getElementById("uploadPreview");

  if (!preview) {
    return;
  }

  if (!file) {
    preview.style.display = "none";

    return;
  }

  preview.src = URL.createObjectURL(file);

  preview.style.display = "block";
});

window.addEventListener("load", async () => {
  const code = getCode();

  if (code) {
    await exchangeCodeForTokens(code);

    window.history.replaceState({}, document.title, "/");
  }

  updateLoginStatus();

  await loadImages();
});
