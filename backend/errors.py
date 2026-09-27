"""API errors with stable, machine-readable codes.

An ApiError is an HTTPException, so the unversioned routes render it through
FastAPI's default handler as {"detail": message}, exactly as before. The /v1
app renders it as {"error": {"code": ..., "message": ...}} (api_v1.py).

Codes are part of the v1 contract: never rename one. Messages are shown to
the user as is and may change.
"""

from fastapi import HTTPException


class ApiError(HTTPException):
    def __init__(self, status_code: int, code: str, message: str):
        super().__init__(status_code=status_code, detail=message)
        self.code = code
