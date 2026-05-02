# send-assignment-notification

Edge Function para enviar por correo la confirmacion de asignacion con el PDF del acta firmada.
Modo único:

1. `MAIL_BRIDGE_URL` (SMTP bridge en PHP/Hostinger)

## Requisitos

- Proyecto Supabase con la tabla `sistema.assignment_acknowledgements`
- Bucket `assignment-documents` con el PDF del acta
- Endpoint SMTP bridge en PHP

## Variables de entorno

Configuralas en Supabase Functions:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `MAIL_BRIDGE_URL` (requerido. Ej: `https://tu-dominio.com/api/send_assignment_mail.php`)
- `MAIL_BRIDGE_TOKEN` (opcional, recomendado para proteger el endpoint)

## Deploy

```bash
supabase functions deploy send-assignment-notification --project-ref TU_PROJECT_REF
```

## Invocacion esperada (desde app)

```json
{
  "assignmentId": "uuid",
  "toEmail": "usuario@empresa.com",
  "assetLabel": "PC-TEST-001 - SN-TEST-001",
  "signerName": "Luis Fernando Ramirez",
  "assignedAt": "2026-04-19T21:30:00+00:00",
  "pdfPath": "assignment/<id>/acta/<file>.pdf"
}
```

## Configuracion con SMTP bridge (ejemplo)

```bash
supabase secrets set MAIL_BRIDGE_URL="https://tu-dominio.com/api/send_assignment_mail.php" --project-ref TU_PROJECT_REF
supabase secrets set MAIL_BRIDGE_TOKEN="TOKEN_LARGO_Y_SEGURO" --project-ref TU_PROJECT_REF
supabase functions deploy send-assignment-notification --no-verify-jwt --project-ref TU_PROJECT_REF
```

El endpoint PHP de ejemplo está en:

- `api_examples/send_assignment_mail.php`


