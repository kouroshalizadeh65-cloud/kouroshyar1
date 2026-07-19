from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime
from typing import Any


@dataclass(frozen=True)
class Article:
    source_name: str
    source_kind: str
    source_url: str
    article_url: str
    title: str
    body: str
    published_at: datetime
    province_hint: str | None = None

    @property
    def combined_text(self) -> str:
        return f"{self.title}\n{self.body}".strip()


@dataclass
class HolidayEvent:
    id: str
    date: str
    title: str
    type: str
    scope: str
    authority: str
    sourceUrl: str
    publishedAt: str
    status: str = "active"
    province: str | None = None
    counties: list[str] = field(default_factory=list)
    excludedCounties: list[str] = field(default_factory=list)
    includedOrganizations: list[str] = field(default_factory=list)
    excludedOrganizations: list[str] = field(default_factory=list)
    note: str | None = None

    def to_json(self) -> dict[str, Any]:
        return {k: v for k, v in asdict(self).items() if v not in (None, [], "")}


@dataclass
class WorkScheduleEvent:
    id: str
    date: str
    title: str
    scheduleType: str
    scope: str
    authority: str
    sourceUrl: str
    publishedAt: str
    status: str = "active"
    province: str | None = None
    counties: list[str] = field(default_factory=list)
    excludedCounties: list[str] = field(default_factory=list)
    endDate: str | None = None
    startTime: str | None = None
    endTime: str | None = None
    includedOrganizations: list[str] = field(default_factory=list)
    excludedOrganizations: list[str] = field(default_factory=list)
    note: str | None = None

    def to_json(self) -> dict[str, Any]:
        return {k: v for k, v in asdict(self).items() if v not in (None, [], "")}


@dataclass
class PendingCandidate:
    articleUrl: str
    source: str
    title: str
    publishedAt: str
    reason: str
    provinceHint: str | None = None
    excerpt: str | None = None

    def to_json(self) -> dict[str, Any]:
        return {k: v for k, v in asdict(self).items() if v not in (None, "")}


@dataclass
class CancellationDirective:
    target: str
    date: str
    scope: str
    title: str
    authority: str
    sourceUrl: str
    publishedAt: str
    province: str | None = None
    counties: list[str] = field(default_factory=list)
    excludedCounties: list[str] = field(default_factory=list)
    includedOrganizations: list[str] = field(default_factory=list)
    excludedOrganizations: list[str] = field(default_factory=list)
    reason: str | None = None

    def to_json(self) -> dict[str, Any]:
        return {k: v for k, v in asdict(self).items() if v not in (None, [], "")}


@dataclass
class ClassificationResult:
    holidays: list[HolidayEvent] = field(default_factory=list)
    work_schedules: list[WorkScheduleEvent] = field(default_factory=list)
    cancellations: list[CancellationDirective] = field(default_factory=list)
    pending: list[PendingCandidate] = field(default_factory=list)
