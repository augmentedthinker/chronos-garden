# GitHub Pages Deployment Guide

This guide explains how to host the exported Godot 4.3 Web build on GitHub Pages.

---

## Technical Highlights

1. **Static Only**: GitHub Pages acts solely as a static file server hosting the WebAssembly and HTML5 assets. It does not run continuous simulations.
2. **Single-Threaded Compatibility**: Exported using Godot 4.3's `variant/thread_support=false` (GL Compatibility). This eliminates the requirement for `SharedArrayBuffer` and `Cross-Origin-Opener-Policy` (COOP/COEP) headers, allowing the application to load cleanly on default GitHub Pages hosting.
3. **CORS-Free Cloud Persistence**: Supabase PostgREST endpoints permit direct client-side cross-origin requests (`Access-Control-Allow-Origin: *`), meaning the browser application communicates directly with Supabase without proxy servers.

---

## Deployment Option 1: Automated GitHub Actions (Recommended)

1. Create a new repository on GitHub (e.g. `persistent-garden`).
2. Push this project folder to your repository:
   ```bash
   git init
   git add .
   git commit -m "Initial commit: Godot persistent garden"
   git branch -M main
   git remote add origin https://github.com/<your-username>/persistent-garden.git
   git push -u origin main
   ```
3. In your GitHub repository:
   - Navigate to **Settings** -> **Pages**.
   - Under **Build and deployment** -> **Source**, select **GitHub Actions**.
4. The workflow in `.github/workflows/deploy.yml` will automatically detect the push, bundle the `build/` directory, and deploy it live to `https://<your-username>.github.io/persistent-garden/`.

---

## Deployment Option 2: Deploying from the `/docs` or Root Folder

If you prefer classic branch publishing without GitHub Actions:
1. In your repo, copy the contents of `build/` into a `docs/` folder:
   ```bash
   mkdir -p docs
   cp -r build/* docs/
   git add docs
   git commit -m "Add web export to docs"
   git push
   ```
2. In GitHub repository **Settings** -> **Pages**:
   - Under **Build and deployment** -> **Source**, select **Deploy from a branch**.
   - Branch: `main`, Folder: `/docs`.
   - Click **Save**.
3. Within 1–2 minutes, your persistent garden will be accessible globally.

---

## Local Verification

Before deploying to GitHub, you can test the exact web build locally via Horizon:
👉 **[http://127.0.0.1:5174/persistent-garden/index.html](http://127.0.0.1:5174/persistent-garden/index.html)**
