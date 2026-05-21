# Restore checklist

This backend has three independent state surfaces:

1. Supabase PostgreSQL
2. Cloudinary raw assets for PDFs / HTML report files
3. Application config on the Droplet

Do not treat a database restore alone as a complete application restore.

## 1. Verify the failure domain

Identify which state is damaged:

- app server only
- database only
- Cloudinary assets only
- combined failure

The recovery plan changes depending on that answer.

## 2. Rebuild the Droplet app layer

If the Droplet is lost but Supabase and Cloudinary are intact:

```bash
sudo DOMAIN=api.example.com bash deploy/digitalocean/bootstrap.sh
nano /srv/flicko/backend/.env
sudo bash /srv/flicko/backend/deploy/digitalocean/update.sh
```

Then verify:

```bash
PUBLIC_HEALTH_URL=https://api.example.com/api/auth/health/ \
sudo bash /srv/flicko/backend/deploy/digitalocean/health-smoke.sh
```

## 3. Restore PostgreSQL from backup

Example using the backup artifact created by `backup.sh`:

```bash
pg_restore \
  --clean \
  --if-exists \
  --no-owner \
  --dbname="$DATABASE_URL" \
  /var/backups/flicko/<timestamp>/postgres.dump
```

After restore:

```bash
cd /srv/flicko/backend
source .venv/bin/activate
python manage.py migrate
python manage.py check
```

Then run health smoke again.

## 4. Validate report file continuity

The DB can restore faster than Cloudinary asset recovery. Check both:

1. DB report rows exist
2. report file API routes still open the assets

Test one owned report through:

- `/api/auth/intake-reports/<id>/pdf/`
- `/api/auth/intake-reports/<id>/html/`

If DB rows exist but assets are missing, the app will return `404` on file access.

## 5. Cloudinary recovery reality

This backend stores PDFs and HTML files in Cloudinary, not on the Droplet.

That means:

- Droplet backups do not restore report binaries
- Postgres backups do not restore report binaries
- you must rely on Cloudinary asset persistence / backup policy / support workflow

The backup script stores a `report_file_manifest.json` so you can identify expected file references after a DB restore.

## 6. Final validation

Minimum post-restore checks:

```bash
sudo bash /srv/flicko/backend/deploy/digitalocean/health-smoke.sh
curl -I https://api.example.com/api/auth/health/
```

Then validate:

1. login works
2. OTP email works
3. create one intake report
4. open generated PDF
5. open generated HTML
