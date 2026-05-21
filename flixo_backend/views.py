from __future__ import annotations

from django.http import HttpResponse, JsonResponse
from django.urls import reverse


def service_root(request):
    health_path = reverse("health")
    payload = {
        "service": "Flicko AI backend",
        "status": "ok",
        "health_url": request.build_absolute_uri(health_path),
        "api_base": request.build_absolute_uri("/api/auth/"),
        "admin_url": request.build_absolute_uri("/admin/"),
    }
    return JsonResponse(payload, status=200)


def favicon(request):
    return HttpResponse(status=204)
