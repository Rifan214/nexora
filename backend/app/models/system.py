from pydantic import BaseModel


class AppInfo(BaseModel):
    name: str
    version: str
    environment: str
    docs_url: str = "/docs"


class HealthStatus(BaseModel):
    status: str
    environment: str


class VersionInfo(BaseModel):
    version: str