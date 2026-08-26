from pathlib import Path


APP_DIR = Path(__file__).resolve().parent.parent


def test_compose_mounts_storedge_for_metube_and_image_api():
    compose = (APP_DIR / "docker-compose.yml").read_text()

    assert "- /mnt/storedge/metube:/downloads/storedge" in compose
    assert "- /mnt/storedge:/data/storedge" in compose
    assert "STOREDGE_IMAGE_STORAGE_PATH=/data/storedge/images/files" in compose
    assert "STOREDGE_SENTINEL_PATH=/data/storedge/.hoarder-storedge" in compose


def test_nfs_export_is_limited_to_newnas_tailnet_address():
    export = (APP_DIR / "storage" / "storedge-newnas.exports").read_text()

    assert export.strip() == (
        "/mnt/core/srv/share/archive "
        "100.123.166.5(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)"
    )


def test_mount_unit_uses_tailscale_name_and_archive_export():
    mount = (APP_DIR / "storage" / "mnt-storedge.mount").read_text()

    assert "After=tailscaled.service network-online.target" in mount
    assert "What=storedge:/mnt/core/srv/share/archive" in mount
    assert "Where=/mnt/storedge" in mount
    assert "Options=rw,hard,_netdev,nosuid,nodev" in mount
