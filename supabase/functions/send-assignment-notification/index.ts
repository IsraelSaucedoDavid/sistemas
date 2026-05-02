import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface Payload {
  assignmentId: string;
  toEmail: string;
  assetLabel: string;
  signerName: string;
  assignedAt?: string | null;
  pdfPath: string;
}

type AckUpdate = {
  email_status: "sent" | "error";
  email_error?: string | null;
  email_sent_at?: string | null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body = (await req.json()) as Payload;
    const assignmentId = body.assignmentId?.trim();
    const toEmail = body.toEmail?.trim();
    const assetLabel = body.assetLabel?.trim();
    const signerName = body.signerName?.trim();
    const pdfPath = body.pdfPath?.trim();
    const assignedAt = body.assignedAt ?? "";

    if (!assignmentId || !toEmail || !assetLabel || !signerName || !pdfPath) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const bridgeUrl = Deno.env.get("MAIL_BRIDGE_URL") ?? "";
    const bridgeToken = Deno.env.get("MAIL_BRIDGE_TOKEN") ?? "";

    if (!supabaseUrl || !serviceKey) {
      return new Response(
        JSON.stringify({ error: "Missing env vars SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const updateAck = async (payload: AckUpdate) => {
      await supabase
        .schema("sistema")
        .from("assignment_acknowledgements")
        .update(payload)
        .eq("assignment_id", assignmentId);
    };

    const { data: fileData, error: downloadError } = await supabase.storage
      .from("assignment-documents")
      .download(pdfPath);
    if (downloadError || !fileData) {
      await updateAck({
        email_status: "error",
        email_error: `No se pudo descargar PDF: ${downloadError?.message ?? "sin archivo"}`,
      });
      return new Response(
        JSON.stringify({ error: "PDF download failed", details: downloadError?.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const arrayBuffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    const binary = Array.from(bytes).map((b) => String.fromCharCode(b)).join("");
    const pdfBase64 = btoa(binary);
    const attachmentFileName = `acta_asignacion_${assignmentId}.pdf`;

    if (!bridgeUrl || bridgeUrl.trim().length === 0) {
      await updateAck({
        email_status: "error",
        email_error: "No hay MAIL_BRIDGE_URL configurado.",
        email_sent_at: null,
      });
      return new Response(
        JSON.stringify({ error: "MAIL_BRIDGE_URL is required" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const bridgeResponse = await fetch(bridgeUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(bridgeToken.trim().length > 0 ? { "X-API-KEY": bridgeToken } : {}),
      },
      body: JSON.stringify({
        assignmentId,
        toEmail,
        assetLabel,
        signerName,
        assignedAt: assignedAt || "-",
        pdfBase64,
        attachmentFileName,
        subject: "Confirmacion de asignacion de equipo TI",
        html:
          `<h2>Asignacion de equipo confirmada</h2>` +
          `<p>Hola ${signerName},</p>` +
          `<p>Tu asignacion de equipo ha sido registrada correctamente.</p>` +
          `<ul>` +
          `<li><b>Activo:</b> ${assetLabel}</li>` +
          `<li><b>Fecha asignacion:</b> ${assignedAt || "-"}</li>` +
          `</ul>` +
          `<p>Se adjunta el PDF del acta firmada.</p>`,
      }),
    });

    const bridgeJson = await bridgeResponse.json().catch(() => ({}));
    if (!bridgeResponse.ok) {
      await updateAck({
        email_status: "error",
        email_error: `MAIL_BRIDGE_ERROR ${bridgeResponse.status}: ${JSON.stringify(bridgeJson)}`,
        email_sent_at: null,
      });
      return new Response(
        JSON.stringify({ error: "Mail bridge failed", details: bridgeJson }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    await updateAck({
      email_status: "sent",
      email_error: null,
      email_sent_at: new Date().toISOString(),
    });

    return new Response(
      JSON.stringify({ ok: true, provider: "smtp_bridge", data: bridgeJson }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: "Unexpected error", details: String(error) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

