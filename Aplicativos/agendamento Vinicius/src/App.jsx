// src/App.jsx — Agendamento Studio Premium

import { useState, useEffect } from "react";
import { io } from "socket.io-client";

const API = "http://localhost:3001/api";
const SOCKET = io("http://localhost:3001", {
  transports: ["websocket", "polling"],
  reconnection: true,
  reconnectionDelay: 2000,
});

// ─── Icons ────────────────────────────────────────────────────
const CheckIcon = () => (
  <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
    <path d="M2 6l3 3 5-5" stroke="white" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>
);

const BellIcon = () => (
  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
    <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
  </svg>
);

const ClockIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="12" cy="12" r="10"/>
    <polyline points="12 6 12 12 16 14"/>
  </svg>
);

const SparkleIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M12 2l2.4 7.4H22l-6.2 4.5 2.4 7.4L12 17l-6.2 4.3 2.4-7.4L2 9.4h7.6z"/>
  </svg>
);

const ArrowIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
    <path d="M5 12h14M12 5l7 7-7 7"/>
  </svg>
);

// ─── Header ───────────────────────────────────────────────────
function StudioHeader({ etapa }) {
  return (
    <header className="studio-header">
      <div className="studio-logo">
        <div className="studio-logo-icon">🌸</div>
        <div>
          <div className="studio-logo-text">Beatris Gomes Studio</div>
          <div className="studio-logo-sub">Extensão de Cílios</div>
        </div>
      </div>
      <div className="progress-bar-wrap">
        {[1, 2, 3].map((step) => (
          <div
            key={step}
            className={`progress-dot ${etapa === step ? "active" : etapa > step ? "done" : ""}`}
          />
        ))}
      </div>
    </header>
  );
}

// ─── Chat Bubble ──────────────────────────────────────────────
function AssistantBubble({ children, delay = 0 }) {
  return (
    <div
      className="bubble-assistant-wrap"
      style={{ animationDelay: `${delay}s` }}
    >
      <div className="bubble-avatar">🌸</div>
      <div className="bubble-assistant">{children}</div>
    </div>
  );
}

function UserBubble({ children }) {
  return (
    <div className="bubble-user-wrap">
      <div className="bubble-user">{children}</div>
    </div>
  );
}

// ─── Service Card ─────────────────────────────────────────────
function ServiceCard({ item, selected, onClick }) {
  return (
    <div
      className={`service-card ${selected ? "selected" : ""}`}
      onClick={onClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => e.key === "Enter" && onClick()}
      aria-pressed={selected}
    >
      <div className="service-check">
        <CheckIcon />
      </div>

      <div className="service-badge">
        <SparkleIcon />
        Premium
      </div>

      <div className="service-name">{item.nome}</div>

      <div style={{ marginTop: "auto", paddingTop: "20px" }}>
        <div className="service-price">
          <sup>R$</sup>
          {item.preco}
          <span style={{ fontSize: "14px", color: "var(--text-muted)", marginLeft: "2px" }}>,00</span>
        </div>
        <div className="service-duration">
          <span style={{ display: "inline-flex", alignItems: "center", gap: "4px" }}>
            <ClockIcon /> {item.duracao}
          </span>
        </div>
      </div>
    </div>
  );
}

// ─── Main App ─────────────────────────────────────────────────
export default function App() {
  const [etapa, setEtapa] = useState(1);
  const [nome, setNome] = useState("");
  const [nomeInput, setNomeInput] = useState("");
  const [phone, setPhone] = useState("");
  const [servicoSelecionado, setServicoSelecionado] = useState(null);
  const [date, setDate] = useState("");
  const [time, setTime] = useState("");
  const [salvando, setSalvando] = useState(false);

  const servicos = [
    { id: 1, nome: "Micropigmentação Shadow", preco: 300},
    { id: 2, nome: "Design personalizado",        preco: 30},
    { id: 3, nome: "Design com hena",                preco: 55 },
    { id: 4, nome: "Brow Lamination sem tintura",                preco: 125 },
    { id: 5, nome: "Brow Lamination com tintura ",                preco: 145 },
    { id: 6, nome: "Depilação buço ",                preco: 17 },
    { id: 7, nome: "Manicure  E Pedicure ",                preco: 60 },
    { id: 8, nome: "Mão ",                preco: 30 },
    { id: 9, nome: "Pé",                preco: 35 },
  ];

  useEffect(() => {
    servicos.forEach((s) => {
      fetch(`${API}/services/`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: s.nome,
          duration: s.duracao === "30min" ? 30 : 60,
          price: s.preco,
          color: "#c9a96e",
        }),
      }).catch(() => {});
    });

    SOCKET.on("connect", () => console.log("[App Agendamento] Conectado ao WebSocket"));
    SOCKET.on("data:changed", (data) => console.log("[App Agendamento] Dados alterados:", data));
    SOCKET.on("appointment:created", (data) => console.log("[App Agendamento] Novo agendamento:", data));

    return () => {
      SOCKET.off("connect");
      SOCKET.off("data:changed");
      SOCKET.off("appointment:created");
    };
  }, []);

  function enviarNome() {
    if (!nomeInput || !phone) return;
    setNome(nomeInput);
    setEtapa(2);
  }

  function ativarNotificacoes() { setEtapa(3); }
  function pularNotificacoes()  { setEtapa(3); }

  async function buscarClientePorNome(nome) {
    const res = await fetch(`${API}/clients/`);
    const clients = await res.json();
    return clients.find((c) => c.name.toLowerCase() === nome.toLowerCase());
  }

  async function finalizarServico() {
    if (!servicoSelecionado || !date || !time) return;
    setSalvando(true);

    try {
      let client = await buscarClientePorNome(nome);

      if (!client) {
        const clientRes = await fetch(`${API}/clients/`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: nome, phone }),
        });
        if (!clientRes.ok) {
          const err = await clientRes.json();
          throw new Error(err.error || "Erro ao criar cliente");
        }
        client = await clientRes.json();
      }

      const apptRes = await fetch(`${API}/appointments/`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: client.id,
          service: servicoSelecionado.nome,
          appointment_date: date,
          appointment_time: time,
          price: servicoSelecionado.preco,
          status: "confirmed",
          duration: servicoSelecionado.duracao === "30min" ? 30 : 60,
        }),
      });

      if (!apptRes.ok) {
        const err = await apptRes.json();
        throw new Error(err.error || "Erro ao criar agendamento");
      }

      alert(
        `Agendamento confirmado!\n\nCliente: ${nome}\nServiço: ${servicoSelecionado.nome}\nData: ${date} às ${time}`
      );

      setNome(""); setNomeInput(""); setPhone("");
      setServicoSelecionado(null); setDate(""); setTime("");
      setEtapa(1);
    } catch (e) {
      alert("Erro ao salvar: " + e.message);
    }

    setSalvando(false);
  }

  // Formatted date for summary
  const formattedDate = date
    ? new Date(date + "T12:00").toLocaleDateString("pt-BR", {
        weekday: "long", day: "numeric", month: "long",
      })
    : "";

  return (
    <div className="app-shell">
      <StudioHeader etapa={etapa} />

      <div className="app-container">

        {/* ── ETAPA 1: Boas-vindas + Nome ── */}
        {etapa === 1 && (
          <div>
            <div className="chat-wrap">
              <AssistantBubble delay={0}>
                Olá, seja muito bem-vinda! ✨ Sou a assistente virtual do{" "}
                <em>Beatriz Gomes Studios</em> — especialistas em extensão de cílios
                e beleza feminina.
              </AssistantBubble>

              <AssistantBubble delay={0.18}>
                Para começar seu agendamento, pode me dizer seu nome e
                telefone? 🌸
              </AssistantBubble>
            </div>

            <div className="form-section">
              <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
                <div>
                  <label className="form-label">Seu nome completo</label>
                  <input
                    type="text"
                    placeholder="Ex: Maria Fernanda"
                    value={nomeInput}
                    onChange={(e) => setNomeInput(e.target.value)}
                    onKeyDown={(e) => e.key === "Enter" && enviarNome()}
                    className="input-field"
                    autoFocus
                  />
                </div>

                <div>
                  <label className="form-label">Telefone com DDD</label>
                  <input
                    type="tel"
                    placeholder="(11) 99999-9999"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    onKeyDown={(e) => e.key === "Enter" && enviarNome()}
                    className="input-field"
                  />
                </div>

                <div style={{ paddingTop: "8px" }}>
                  <button
                    onClick={enviarNome}
                    className="btn-primary"
                    disabled={!nomeInput || !phone}
                  >
                    <span className="btn-icon">
                      Continuar <ArrowIcon />
                    </span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* ── ETAPA 2: Notificações ── */}
        {etapa === 2 && (
          <div>
            <div className="chat-wrap">
              <UserBubble>{nome}</UserBubble>

              <AssistantBubble delay={0.1}>
                Que nome lindo, <em>{nome}</em>! Prazer em te receber. 💫
              </AssistantBubble>

              <AssistantBubble delay={0.25}>
                Para não perder nenhum detalhe do seu agendamento, quer
                ativar as notificações de lembrete?
              </AssistantBubble>
            </div>

            <div className="form-section">
              <div className="notif-card">
                <div className="notif-icon rose">🔔</div>
                <div className="notif-text">
                  <h4>Lembrete de agendamento</h4>
                  <p>Você receberá um aviso 24h antes da sua visita ao studio.</p>
                </div>
              </div>

              <div className="notif-card">
                <div className="notif-icon gold">✨</div>
                <div className="notif-text">
                  <h4>Novidades e promoções</h4>
                  <p>Fique por dentro das ofertas exclusivas do studio.</p>
                </div>
              </div>

              <div style={{ display: "flex", flexDirection: "column", gap: "12px", marginTop: "24px" }}>
                <button onClick={ativarNotificacoes} className="btn-primary">
                  <span className="btn-icon">
                    <BellIcon /> Ativar notificações
                  </span>
                </button>
                <button onClick={pularNotificacoes} className="btn-secondary">
                  Pular por agora
                </button>
              </div>
            </div>
          </div>
        )}

        {/* ── ETAPA 3: Serviços + Data/Hora ── */}
        {etapa === 3 && (
          <div>
            <div className="chat-wrap">
              <AssistantBubble delay={0}>
                Perfeito! Agora me diga qual serviço você deseja agendar. 💅
              </AssistantBubble>
            </div>

            <div className="form-section">
              <div className="section-eyebrow">Serviços disponíveis</div>
              <div className="section-title">O que você procura?</div>

              <div className="services-scroll">
                {servicos.map((item, i) => (
                  <div
                    key={item.id}
                    style={{ animationDelay: `${i * 0.08}s` }}
                    className="fadeUp"
                  >
                    <ServiceCard
                      item={item}
                      selected={servicoSelecionado?.id === item.id}
                      onClick={() => setServicoSelecionado(item)}
                    />
                  </div>
                ))}
              </div>

              <div className="scroll-hint">
                <span>deslize para ver mais</span>
                <div className="scroll-hint-line" />
                <span>→</span>
              </div>

              <div className="divider">
                <div className="divider-text">escolha data e horário</div>
              </div>

              <div className="datetime-grid">
                <div>
                  <label className="form-label">📅 Data</label>
                  <input
                    type="date"
                    value={date}
                    onChange={(e) => setDate(e.target.value)}
                    className="input-field"
                    min={new Date().toISOString().split("T")[0]}
                  />
                </div>
                <div>
                  <label className="form-label">🕐 Horário</label>
                  <input
                    type="time"
                    value={time}
                    onChange={(e) => setTime(e.target.value)}
                    className="input-field"
                  />
                </div>
              </div>

              {/* Summary preview */}
              {servicoSelecionado && date && time && (
                <div className="summary-card" style={{ animationDelay: "0.1s" }}>
                  <div className="deco-line" />
                  <div style={{ marginBottom: "16px" }}>
                    <div className="section-eyebrow">Resumo do agendamento</div>
                  </div>
                  <div className="summary-row">
                    <span className="summary-label">Serviço</span>
                    <span className="summary-value">{servicoSelecionado.nome}</span>
                  </div>
                  <div className="summary-row">
                    <span className="summary-label">Valor</span>
                    <span className="summary-value">R$ {servicoSelecionado.preco},00</span>
                  </div>
                  <div className="summary-row">
                    <span className="summary-label">Data</span>
                    <span className="summary-value" style={{ textTransform: "capitalize" }}>{formattedDate}</span>
                  </div>
                  <div className="summary-row">
                    <span className="summary-label">Horário</span>
                    <span className="summary-value">{time}</span>
                  </div>
                  <div className="summary-row">
                    <span className="summary-label">Duração</span>
                    <span className="summary-value">{servicoSelecionado.duracao}</span>
                  </div>
                </div>
              )}

              <div style={{ marginTop: "24px" }}>
                <button
                  onClick={finalizarServico}
                  disabled={salvando || !servicoSelecionado || !date || !time}
                  className="btn-primary"
                >
                  {salvando ? (
                    <span className="btn-icon">
                      Confirmando
                      <span className="loading-dots">
                        <span /><span /><span />
                      </span>
                    </span>
                  ) : (
                    <span className="btn-icon">
                      Confirmar agendamento <ArrowIcon />
                    </span>
                  )}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
