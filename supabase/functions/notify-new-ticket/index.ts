import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.0'
import { GoogleAuth } from 'npm:google-auth-library'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Manejar CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. Recibir los datos del ticket (ya sea por Webhook o llamado directo)
    const payload = await req.json()
    console.log("Recibido payload:", payload)

    // El registro puede venir en payload.record (si es Webhook) o directo
    const ticket = payload.record || payload
    
    if (!ticket.asunto) {
      throw new Error("El ticket no tiene asunto")
    }

    // 2. Conectar a Supabase como Administrador para leer tokens
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 3. Buscar los tokens de los dispositivos registrados
    const { data: userTokens, error: dbError } = await supabaseClient
      .from('user_tokens')
      .select('fcm_token')

    if (dbError) throw dbError

    if (!userTokens || userTokens.length === 0) {
      console.log("No hay tokens registrados en la base de datos.")
      return new Response(JSON.stringify({ message: "No hay tokens" }), { status: 200 })
    }

    // 4. Autenticación con Google usando el Secreto guardado
    const serviceAccountSecret = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!serviceAccountSecret) {
      throw new Error("No se encontró el secreto FIREBASE_SERVICE_ACCOUNT")
    }
    
    // SOLUCIÓN NUCLEAR: Extraer solo lo que está entre el primer { y el último }
    const match = serviceAccountSecret.match(/\{[\s\S]*\}/)
    if (!match) {
      throw new Error("El secreto no contiene un JSON válido (faltan llaves { })")
    }
    
    const cleanSecret = match[0]
    const serviceAccount = JSON.parse(cleanSecret)
    const auth = new GoogleAuth({
      credentials: {
        client_email: serviceAccount.client_email,
        private_key: serviceAccount.private_key.replace(/\\n/g, '\n'),
      },
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })

    const accessToken = await auth.getAccessToken()
    const projectId = serviceAccount.project_id
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

    console.log(`Enviando notificación a ${userTokens.length} dispositivos...`)

    // 5. Enviar la notificación a cada dispositivo
    const results = []
    for (const row of userTokens) {
      const message = {
        message: {
          token: row.fcm_token,
          notification: {
            title: "Nuevo Ticket de Soporte",
            body: `Asunto: ${ticket.asunto}`
          },
          data: {
            ticket_id: String(ticket.ticket_id || ticket.id || ""),
            click_action: "FLUTTER_NOTIFICATION_CLICK"
          },
          android: {
            priority: "high",
            notification: {
              channel_id: "tickets_channel"
            }
          }
        }
      }

      const res = await fetch(fcmUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(message),
      })
      
      const resData = await res.json()
      results.push({ token: row.fcm_token.substring(0, 10) + "...", status: res.status, data: resData })
    }

    return new Response(JSON.stringify({ success: true, results }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (err) {
    console.error("Error crítico en notify-new-ticket:", err.message)
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
