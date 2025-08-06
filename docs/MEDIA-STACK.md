# Media Stack Configuration Guide

## Overview

The media stack consists of:
- **SABnzbd** - Usenet downloader
- **Prowlarr** - Indexer management (manages all your torrent/usenet indexers)
- **Sonarr** - TV show automation
- **Radarr** - Movie automation
- **Bazarr** - Subtitle automation
- **Jellyfin** - Media server
- **Overseerr** - Request management

## Architecture

```
Internet → Overseerr (Public)
             ↓
         Sonarr/Radarr
             ↓
         Prowlarr → Indexers
             ↓
         SABnzbd → Downloads
             ↓
         Media Storage
             ↓
         Jellyfin → Streaming
```

## Initial Setup

### 1. Configure Usenet Provider

Edit `apps/media/sabnzbd.yaml` and update the secret:

```yaml
stringData:
  NEWS_SERVER_HOST: "your-provider.com"
  NEWS_SERVER_PORT: "563"
  NEWS_SERVER_USERNAME: "your-username"
  NEWS_SERVER_PASSWORD: "your-password"
```

Popular providers: Newshosting, Eweka, UsenetServer

### 2. Deploy the Stack

```bash
cd apps/media
./deploy-media-stack.sh
```

### 3. Configure SABnzbd

1. Access https://sabnzbd.mackie.house
2. Complete the setup wizard
3. Note the API key from Config → General
4. Configure categories:
   - `tv` → `/downloads/complete/tv`
   - `movies` → `/downloads/complete/movies`

### 4. Configure Prowlarr

1. Access https://prowlarr.mackie.house
2. Add indexers:
   - Settings → Indexers → Add
   - Popular: NZBgeek, NZBFinder, DrunkenSlug
3. Add applications:
   - Settings → Apps → Add
   - Add Sonarr and Radarr with their API keys

### 5. Configure Sonarr

1. Access https://sonarr.mackie.house
2. Settings → Media Management:
   - Root folder: `/tv`
   - Enable "Rename Episodes"
3. Settings → Download Clients:
   - Add SABnzbd with API key
   - Category: `tv`
4. Settings → Indexers:
   - Should auto-populate from Prowlarr

### 6. Configure Radarr

1. Access https://radarr.mackie.house
2. Settings → Media Management:
   - Root folder: `/movies`
   - Enable "Rename Movies"
3. Settings → Download Clients:
   - Add SABnzbd with API key
   - Category: `movies`
4. Settings → Indexers:
   - Should auto-populate from Prowlarr

### 7. Configure Bazarr

1. Access https://bazarr.mackie.house
2. Settings → Sonarr:
   - Add Sonarr URL and API key
3. Settings → Radarr:
   - Add Radarr URL and API key
4. Settings → Subtitles:
   - Add providers (OpenSubtitles, Subscene, etc.)

### 8. Configure Jellyfin

1. Access https://jellyfin.mackie.house
2. Complete initial setup wizard
3. Add media libraries:
   - Movies → `/media/movies`
   - TV Shows → `/media/tv`
4. Enable hardware acceleration if available

### 9. Configure Overseerr

1. Access https://requests.mackie.house
2. Sign in with Jellyfin account
3. Configure services:
   - Add Sonarr/Radarr connections
   - Set up user permissions
   - Configure notification agents

## File Organization

The stack uses this structure:
```
/media/
├── movies/
│   ├── Movie Name (Year)/
│   │   └── Movie.Name.Year.1080p.mkv
├── tv/
│   ├── Show Name/
│   │   ├── Season 01/
│   │   │   └── S01E01.mkv
/downloads/
├── complete/
│   ├── movies/
│   └── tv/
└── incomplete/
```

## API Keys Reference

Each service has an API key found at:
- **SABnzbd**: Config → General → API Key
- **Sonarr**: Settings → General → API Key
- **Radarr**: Settings → General → API Key
- **Prowlarr**: Settings → General → API Key
- **Jellyfin**: Dashboard → API Keys
- **Overseerr**: Settings → General → API Key

## Automation Workflow

1. User requests media via Overseerr
2. Overseerr sends request to Sonarr/Radarr
3. Sonarr/Radarr searches via Prowlarr
4. Prowlarr queries all configured indexers
5. Best result sent to SABnzbd
6. SABnzbd downloads to `/downloads`
7. Sonarr/Radarr imports to `/media`
8. Bazarr downloads subtitles
9. Jellyfin serves the media

## Performance Tuning

### SABnzbd
- Connections: 20-50 (depends on provider)
- Article cache: 1GB+
- Enable DirectUnpack

### Sonarr/Radarr
- Set quality profiles appropriately
- Configure preferred words for better releases
- Set up recycling bin to prevent re-downloads

### Jellyfin
- Enable hardware transcoding if GPU available
- Pre-transcode popular content
- Configure appropriate streaming bitrates

## Troubleshooting

### Downloads not starting
- Check SABnzbd has valid Usenet credentials
- Verify Prowlarr indexers are working
- Check API keys are correct

### Media not importing
- Verify download paths match in all services
- Check file permissions (PUID/PGID)
- Look for import errors in Sonarr/Radarr logs

### Jellyfin not seeing files
- Rescan libraries
- Check file permissions
- Verify media paths are correct

## Monitoring

Add these to Grafana:
- SABnzbd queue size and speed
- Sonarr/Radarr queue and health
- Jellyfin active streams
- Storage usage trends

## Backup Considerations

Critical data to backup:
- All config volumes (automated via Longhorn)
- Prowlarr indexer configurations
- Sonarr/Radarr series/movie lists
- Jellyfin user data and metadata