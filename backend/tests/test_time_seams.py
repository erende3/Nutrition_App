from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest
from fastapi import HTTPException

import config
from dependencies import get_request_timezone
from services import clock


def test_utc_now_is_aware_utc():
    now = clock.utc_now()

    assert now.utcoffset() == timedelta(0)
    assert abs(now - datetime.now(timezone.utc)) < timedelta(seconds=5)


def test_local_today_is_the_date_in_the_given_zone(monkeypatch):
    # 03:30 UTC on Sep 26 is still 23:30 on Sep 25 in New York.
    monkeypatch.setattr(
        clock, "utc_now", lambda: datetime(2026, 9, 26, 3, 30, tzinfo=timezone.utc)
    )

    assert clock.local_today(ZoneInfo("America/New_York")).isoformat() == "2026-09-25"
    assert clock.local_today(ZoneInfo("UTC")).isoformat() == "2026-09-26"


def test_request_timezone_comes_from_the_header():
    assert get_request_timezone(x_timezone="Asia/Tokyo") == ZoneInfo("Asia/Tokyo")


@pytest.mark.parametrize("header", [None, ""])
def test_request_timezone_defaults_to_the_server_setting(monkeypatch, header):
    monkeypatch.setattr(config, "DEFAULT_TIMEZONE", "Europe/Paris")

    assert get_request_timezone(x_timezone=header) == ZoneInfo("Europe/Paris")


@pytest.mark.parametrize("header", ["Mars/Olympus_Mons", "America", "../../etc/passwd"])
def test_unknown_request_timezone_is_a_client_error(header):
    with pytest.raises(HTTPException) as error:
        get_request_timezone(x_timezone=header)

    assert error.value.status_code == 400
