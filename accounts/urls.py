from django.urls import path

from .views import (
    ForgotPasswordStartView,
    HealthAppRecordCollectionView,
    HealthAppRecordDetailView,
    HealthAppDataCleanupView,
    HealthAppDataView,
    HealthCorpusSearchView,
    HealthMemoryEntryView,
    HealthIntakeReportView,
    HealthProtocolDetailView,
    HealthProtocolEngineContextView,
    GoogleLoginView,
    SystemHealthView,
    LoginView,
    MeView,
    PasswordResetConfirmView,
    RegisterStartView,
    RegisterVerifyView,
)


urlpatterns = [
    path("health/", SystemHealthView.as_view(), name="health"),
    path("register/start/", RegisterStartView.as_view(), name="register-start"),
    path("register/verify/", RegisterVerifyView.as_view(), name="register-verify"),
    path("login/", LoginView.as_view(), name="login"),
    path("google/", GoogleLoginView.as_view(), name="google-login"),
    path("password/forgot/start/", ForgotPasswordStartView.as_view(), name="forgot-start"),
    path("password/reset/", PasswordResetConfirmView.as_view(), name="password-reset"),
    path("me/", MeView.as_view(), name="me"),
    path("app-data/", HealthAppDataView.as_view(), name="health-app-data"),
    path(
        "app-data/cleanup/",
        HealthAppDataCleanupView.as_view(),
        name="health-app-data-cleanup",
    ),
    path(
        "app-data/<str:record_type>/",
        HealthAppRecordCollectionView.as_view(),
        name="health-app-records",
    ),
    path(
        "app-data/<str:record_type>/<path:external_id>/",
        HealthAppRecordDetailView.as_view(),
        name="health-app-record-detail",
    ),
    path("memory/", HealthMemoryEntryView.as_view(), name="health-memory"),
    path("corpus/search/", HealthCorpusSearchView.as_view(), name="health-corpus-search"),
    path(
        "corpus/protocols/<str:protocol_id>/",
        HealthProtocolDetailView.as_view(),
        name="health-protocol-detail",
    ),
    path(
        "protocol-engine/context/",
        HealthProtocolEngineContextView.as_view(),
        name="protocol-engine-context",
    ),
    path("intake-reports/", HealthIntakeReportView.as_view(), name="intake-reports"),
]
