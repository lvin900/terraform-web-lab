#!/bin/bash
# Runs once at first boot. Terraform fills in api_url before the instance launches.
dnf install -y httpd

cat > /var/www/html/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Terraform Web Lab</title>
<style>
  body { font-family: system-ui, -apple-system, Segoe UI, sans-serif; max-width: 520px; margin: 48px auto; padding: 0 16px; color: #1f2937; background: #ffffff; }
  h1 { font-size: 1.6rem; margin-bottom: 4px; }
  p.sub { color: #6b7280; margin-top: 0; }
  label { display: block; font-weight: 600; margin: 16px 0 6px; }
  input, textarea { width: 100%; box-sizing: border-box; padding: 10px; border: 1px solid #d1d5db; border-radius: 6px; font: inherit; }
  textarea { min-height: 96px; resize: vertical; }
  button { margin-top: 16px; padding: 10px 18px; border: 0; border-radius: 6px; background: #2563eb; color: #ffffff; font: inherit; font-weight: 600; cursor: pointer; }
  button:disabled { opacity: 0.6; cursor: default; }
  #status { margin-top: 14px; min-height: 1.2em; }
  .ok { color: #047857; }
  .err { color: #b91c1c; }
</style>
</head>
<body>
<h1>Hello from Terraform</h1>
<p class="sub">Built by Lemuel on AWS. Leave your name and it goes straight to my inbox.</p>

<form id="contact">
  <label for="name">Your name</label>
  <input id="name" name="name" maxlength="100" required autocomplete="name">

  <label for="message">Message (optional)</label>
  <textarea id="message" name="message" maxlength="1000"></textarea>

  <button type="submit" id="send">Send</button>
  <div id="status" role="status"></div>
</form>

<script>
  var API_URL = "${api_url}/contact";
  var form = document.getElementById("contact");
  var statusEl = document.getElementById("status");
  var button = document.getElementById("send");

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    button.disabled = true;
    statusEl.className = "";
    statusEl.textContent = "Sending...";

    fetch(API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: document.getElementById("name").value,
        message: document.getElementById("message").value
      })
    })
      .then(function (r) {
        return r.json().then(function (d) { return { ok: r.ok, data: d }; });
      })
      .then(function (res) {
        if (res.ok) {
          statusEl.className = "ok";
          statusEl.textContent = "Thanks! Your message was sent.";
          form.reset();
        } else {
          statusEl.className = "err";
          statusEl.textContent = res.data.error || res.data.message || "Something went wrong.";
        }
      })
      .catch(function () {
        statusEl.className = "err";
        statusEl.textContent = "Could not reach the server. Please try again.";
      })
      .finally(function () {
        button.disabled = false;
      });
  });
</script>
</body>
</html>
HTML

systemctl enable --now httpd
