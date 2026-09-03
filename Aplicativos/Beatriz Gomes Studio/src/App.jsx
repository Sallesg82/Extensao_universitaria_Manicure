import { useState, useEffect, useRef, useCallback } from "react";
import { io } from "socket.io-client";

const API = import.meta.env.VITE_API_URL || "http://localhost:3001/api";
const SOCKET = io(API.replace(/\/api\/?$/, ""), {
  transports: ["websocket", "polling"],
  reconnection: true,
  reconnectionDelay: 2000,
});

const CheckIcon = () => (
  <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
    <path d="M2 6l3 3 5-5" stroke="white" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
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

const BackIcon = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M19 12H5M12 19l-7-7 7-7"/>
  </svg>
);

function StudioHeader({ etapa, onBack }) {
  return (
    <header className="studio-header">
      <div className="studio-logo">
        {etapa > 1 && (
          <button
            type="button"
            className="header-back-btn"
            onClick={onBack}
            aria-label="Voltar à etapa anterior"
            title="Voltar"
          >
            <BackIcon />
          </button>
        )}
        <div className="studio-logo-icon">🌸</div>
        <div>
          <div className="studio-logo-text">Beatriz Gomes Studio</div>
          <div className="studio-logo-sub">Extensão de Cílios</div>
        </div>
      </div>
      <div className="progress-bar-wrap" aria-label={`Etapa ${etapa} de 2`}>
        {[1, 2].map((step) => (
          <div
            key={step}
            className={`progress-dot ${etapa === step ? "active" : etapa > step ? "done" : ""}`}
            title={`Etapa ${step}`}
          />
        ))}
      </div>
    </header>
  );
}

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

function formatPriceParts(price) {
  const num = Number(price) || 0;
  const [inteiro, cents] = num.toFixed(2).split(".");
  return { inteiro, cents };
}

function ServiceCard({ item, selected, onClick }) {
  const { inteiro, cents } = formatPriceParts(item.preco);

  return (
    <div
      className={`service-card ${selected ? "selected" : ""}`}
      onClick={onClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onClick();
        }
      }}
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
          {inteiro}
          <span style={{ fontSize: "14px", color: "var(--text-muted)", marginLeft: "2px" }}>,{cents}</span>
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

function formatDuracao(min) {
  if (min >= 60) {
    const h = Math.floor(min / 60);
    const m = min % 60;
    return m ? `${h}h${m}` : `${h}h`;
  }
  return `${min}min`;
}

function getLocalDateString(d = new Date()) {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function formatFullDate(dateStr) {
  if (!dateStr) return "";
  const parts = dateStr.split("-");
  if (parts.length !== 3) return dateStr;
  const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0);
  const formatted = d.toLocaleDateString("pt-BR", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
  return formatted.charAt(0).toUpperCase() + formatted.slice(1);
}

function formatPhoneNumber(val) {
  const digits = val.replace(/\D/g, "").slice(0, 11);
  if (digits.length <= 2) return digits;
  if (digits.length <= 7) return `(${digits.slice(0, 2)}) ${digits.slice(2)}`;
  if (digits.length <= 10) {
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`;
  }
  return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7, 11)}`;
}

function SuccessModal({ data, onClose }) {
  const dateFormatted = formatFullDate(data?.date);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <div className="modal-glow" />
        <div className="modal-check">
          <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
            <circle cx="16" cy="16" r="16" fill="url(#check-grad)" />
            <path d="M9 17l5 5 9-9" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
            <defs>
              <linearGradient id="check-grad" x1="0" y1="0" x2="32" y2="32">
                <stop stopColor="#e8a0b4" />
                <stop offset="1" stopColor="#c9a96e" />
              </linearGradient>
            </defs>
          </svg>
        </div>

        <h2 className="modal-title">Agendamento Confirmado!</h2>
        <p className="modal-sub">Seu horário foi reservado com sucesso</p>

        <div className="modal-details">
          <div className="modal-row">
            <span className="modal-label">Cliente</span>
            <span className="modal-value">{data?.cliente}</span>
          </div>
          <div className="modal-row">
            <span className="modal-label">Serviço</span>
            <span className="modal-value">{data?.servico}</span>
          </div>
          <div className="modal-row">
            <span className="modal-label">Data</span>
            <span className="modal-value">{dateFormatted}</span>
          </div>
          <div className="modal-row">
            <span className="modal-label">Horário</span>
            <span className="modal-value">{data?.horario}</span>
          </div>
        </div>

        <button className="btn-primary" onClick={onClose} style={{ marginTop: "24px" }}>
          <span className="btn-icon">Perfeito! ✨</span>
        </button>
      </div>
    </div>
  );
}

export default function App() {
  const [etapa, setEtapa] = useState(1);
  const [nome, setNome] = useState("");
  const [nomeInput, setNomeInput] = useState("");
  const [phone, setPhone] = useState("");
  const [servicoSelecionado, setServicoSelecionado] = useState(null);
  const [date, setDate] = useState("");
  const [time, setTime] = useState("");
  const [salvando, setSalvando] = useState(false);
  const [showSuccess, setShowSuccess] = useState(false);
  const [successData, setSuccessData] = useState(null);
  const [availableSlots, setAvailableSlots] = useState([]);
  const [loadingSlots, setLoadingSlots] = useState(false);
  const [slotsError, setSlotsError] = useState("");
  const [dataInfo, setDataInfo] = useState(null);
  const [servicos, setServicos] = useState([]);
  const [loadingServicos, setLoadingServicos] = useState(true);
  const [errorMsg, setErrorMsg] = useState("");

  const servicoRef = useRef(servicoSelecionado);
  const dateRef = useRef(date);

  useEffect(() => {
    servicoRef.current = servicoSelecionado;
  }, [servicoSelecionado]);

  useEffect(() => {
    dateRef.current = date;
  }, [date]);

  const carregarServicos = useCallback(() => {
    fetch(API + "/services/")
      .then((r) => {
        if (!r.ok) throw new Error("Erro ao consultar serviços");
        return r.json();
      })
      .then((data) => {
        if (Array.isArray(data)) {
          setServicos(
            data.map((s) => ({
              id: s.id,
              nome: s.name,
              preco: s.price,
              duracao: s.duration,
              buffer: s.buffer || 0,
            }))
          );
        } else {
          setServicos([]);
        }
      })
      .catch((err) => {
        console.error("Erro ao carregar serviços:", err);
        setServicos([]);
      })
      .finally(() => setLoadingServicos(false));
  }, []);

  useEffect(() => {
    carregarServicos();
  }, [carregarServicos]);

  const buscarHorarios = useCallback((svc, dataEscolhida) => {
    if (!svc || !dataEscolhida) return;
    const dur = svc.duracao;
    const buf = svc.buffer || 0;

    fetch(`${API}/available-slots?date=${dataEscolhida}&duration=${dur}&buffer=${buf}`)
      .then((r) => {
        if (!r.ok) throw new Error("Erro ao buscar horários");
        return r.json();
      })
      .then((data) => {
        if (data.closed) {
          setAvailableSlots([]);
          setDataInfo({ closed: true, message: data.message || "Fechado neste dia" });
          setSlotsError("");
        } else if (!data.slots || data.slots.length === 0) {
          setAvailableSlots([]);
          setDataInfo({ closed: false, open: data.open, close: data.close });
          setSlotsError("Nenhum horário disponível nesta data.");
        } else {
          setAvailableSlots(data.slots);
          setDataInfo({ closed: false, open: data.open, close: data.close });
          setSlotsError("");
        }
      })
      .catch(() => {
        setAvailableSlots([]);
        setSlotsError("Erro ao buscar horários para esta data.");
      })
      .finally(() => {
        setLoadingSlots(false);
      });
  }, []);

  useEffect(() => {
    if (!servicoSelecionado || !date) return;
    buscarHorarios(servicoSelecionado, date);
  }, [servicoSelecionado, date, buscarHorarios]);

  useEffect(() => {
    const onDataChanged = (data) => {
      console.log("[App Agendamento] Dados alterados:", data);
      if (data?.type === "service") {
        carregarServicos();
      } else if (data?.type === "appointment" && servicoRef.current && dateRef.current) {
        setLoadingSlots(true);
        buscarHorarios(servicoRef.current, dateRef.current);
      }
    };

    const onApptCreated = (data) => {
      console.log("[App Agendamento] Novo agendamento:", data);
      if (servicoRef.current && dateRef.current) {
        setLoadingSlots(true);
        buscarHorarios(servicoRef.current, dateRef.current);
      }
    };

    SOCKET.on("data:changed", onDataChanged);
    SOCKET.on("appointment:created", onApptCreated);

    return () => {
      SOCKET.off("data:changed", onDataChanged);
      SOCKET.off("appointment:created", onApptCreated);
    };
  }, [carregarServicos, buscarHorarios]);

  const phoneDigits = phone.replace(/\D/g, "");
  const canContinue = nomeInput.trim().length >= 2 && phoneDigits.length >= 10;

  function enviarNome() {
    if (!canContinue) return;
    setNome(nomeInput.trim());
    setEtapa(2);
    setErrorMsg("");
  }

  function voltarParaIdentificacao() {
    setEtapa(1);
    setErrorMsg("");
  }

  async function buscarCliente(clientNome, clientPhone) {
    try {
      const res = await fetch(`${API}/clients/`);
      if (!res.ok) return null;
      const clients = await res.json();
      if (!Array.isArray(clients)) return null;

      const cleanPhone = clientPhone.replace(/\D/g, "");
      const cleanName = clientNome.trim().toLowerCase();

      if (cleanPhone) {
        const matchByPhone = clients.find(
          (c) => (c.phone || "").replace(/\D/g, "") === cleanPhone
        );
        if (matchByPhone) return matchByPhone;
      }

      return clients.find(
        (c) => (c.name || "").trim().toLowerCase() === cleanName
      );
    } catch {
      return null;
    }
  }

  async function finalizarServico() {
    if (!servicoSelecionado || !date || !time || salvando) return;
    setSalvando(true);
    setErrorMsg("");

    try {
      const cleanNome = nome.trim();
      const cleanPhone = phone.trim();

      let client = await buscarCliente(cleanNome, cleanPhone);

      if (!client) {
        const clientRes = await fetch(`${API}/clients/`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: cleanNome, phone: cleanPhone }),
        });
        if (!clientRes.ok) {
          const errData = await clientRes.json().catch(() => ({}));
          const detailMsg = Array.isArray(errData.details)
            ? errData.details.join(", ")
            : errData.error || "Erro ao cadastrar cliente";
          throw new Error(detailMsg);
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
          duration: servicoSelecionado.duracao,
        }),
      });

      if (!apptRes.ok) {
        const errData = await apptRes.json().catch(() => ({}));
        throw new Error(errData.error || "Erro ao criar agendamento");
      }

      setSuccessData({
        cliente: cleanNome,
        servico: servicoSelecionado.nome,
        date: date,
        horario: time,
      });
      setShowSuccess(true);

      setNome("");
      setNomeInput("");
      setPhone("");
      setServicoSelecionado(null);
      setDate("");
      setTime("");
      setAvailableSlots([]);
      setDataInfo(null);
      setSlotsError("");
      setEtapa(1);
    } catch (e) {
      setErrorMsg(e.message || "Erro ao confirmar agendamento");
    } finally {
      setSalvando(false);
    }
  }

  const todayStr = getLocalDateString();
  const isToday = date === todayStr;

  const visibleSlots = availableSlots.filter((slot) => {
    if (!isToday) return true;
    const now = new Date();
    const currentMinutes = now.getHours() * 60 + now.getMinutes();
    const [h, m] = slot.split(":").map(Number);
    const slotMinutes = h * 60 + m;
    return slotMinutes > currentMinutes + 15;
  });

  const formattedDate = formatFullDate(date);

  function closeSuccess() {
    setShowSuccess(false);
    setSuccessData(null);
  }

  return (
    <div className="app-shell">
      {showSuccess && <SuccessModal data={successData} onClose={closeSuccess} />}
      <StudioHeader etapa={etapa} onBack={voltarParaIdentificacao} />

      <main className="app-container">
        {etapa === 1 && (
          <div>
            <div className="chat-wrap">
              <AssistantBubble delay={0}>
                Olá, seja muito bem-vinda! ✨ Sou a assistente virtual do{" "}
                <em>Beatriz Gomes Studio</em> — especialistas em extensão de cílios
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
                  <label htmlFor="input-nome" className="form-label">Seu nome completo</label>
                  <input
                    id="input-nome"
                    type="text"
                    placeholder="Ex: Maria Fernanda"
                    value={nomeInput}
                    onChange={(e) => setNomeInput(e.target.value)}
                    onKeyDown={(e) => e.key === "Enter" && canContinue && enviarNome()}
                    className="input-field"
                    autoFocus
                  />
                </div>

                <div>
                  <label htmlFor="input-phone" className="form-label">Telefone com DDD</label>
                  <input
                    id="input-phone"
                    type="tel"
                    placeholder="(11) 99999-9999"
                    value={phone}
                    onChange={(e) => setPhone(formatPhoneNumber(e.target.value))}
                    onKeyDown={(e) => e.key === "Enter" && canContinue && enviarNome()}
                    className="input-field"
                  />
                  <span style={{ fontSize: "11px", color: "var(--text-muted)", marginTop: "4px", display: "block" }}>
                    Utilizaremos para enviar os detalhes do seu agendamento.
                  </span>
                </div>

                <div style={{ paddingTop: "8px" }}>
                  <button
                    onClick={enviarNome}
                    className="btn-primary"
                    disabled={!canContinue}
                  >
                    <span className="btn-icon">
                      Escolher serviço <ArrowIcon />
                    </span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {etapa === 2 && (
          <div>
            <div className="chat-wrap">
              <UserBubble>{nome}</UserBubble>

              <div style={{ display: "flex", justifyContent: "flex-end" }}>
                <div className="client-chip">
                  <span>👤 {nome} • {phone}</span>
                  <button
                    type="button"
                    className="btn-chip-edit"
                    onClick={voltarParaIdentificacao}
                  >
                    Alterar
                  </button>
                </div>
              </div>

              <AssistantBubble delay={0.1}>
                Que prazer te receber, <em>{nome}</em>! 💫 Qual serviço você deseja agendar hoje?
              </AssistantBubble>
            </div>

            <div className="form-section">
              <div className="section-eyebrow">Serviços disponíveis</div>
              <div className="section-title">O que você procura?</div>

              {loadingServicos ? (
                <div className="slots-loading">
                  <span className="loading-dots"><span /><span /><span /></span>
                  <span style={{ marginLeft: "8px", color: "var(--text-muted)" }}>Carregando serviços...</span>
                </div>
              ) : servicos.length === 0 ? (
                <div className="slots-empty">
                  <span style={{ fontSize: "32px" }}>💅</span>
                  <p>Nenhum serviço disponível no momento.</p>
                </div>
              ) : (
                <div className="services-scroll">
                  {servicos.map((item, i) => (
                    <div
                      key={item.id}
                      style={{ animationDelay: `${i * 0.08}s` }}
                      className="fadeUp"
                    >
                      <ServiceCard
                        item={{ ...item, duracao: formatDuracao(item.duracao) }}
                        selected={servicoSelecionado?.id === item.id}
                        onClick={() => {
                          setServicoSelecionado(item);
                          setTime("");
                          setAvailableSlots([]);
                          setDataInfo(null);
                          setSlotsError("");
                          setErrorMsg("");
                          if (date) setLoadingSlots(true);
                        }}
                      />
                    </div>
                  ))}
                </div>
              )}

              <div className="scroll-hint">
                <span>deslize para ver mais</span>
                <div className="scroll-hint-line" />
                <span>→</span>
              </div>

              {servicoSelecionado && (
                <>
                  <div className="divider">
                    <div className="divider-text">escolha a data</div>
                  </div>

                  <div style={{ marginBottom: "16px" }}>
                    <label htmlFor="input-date" className="form-label">📅 Data do agendamento</label>
                    <input
                      id="input-date"
                      type="date"
                      value={date}
                      onChange={(e) => {
                        const val = e.target.value;
                        setDate(val);
                        setTime("");
                        setAvailableSlots([]);
                        setDataInfo(null);
                        setSlotsError("");
                        setErrorMsg("");
                        if (val) setLoadingSlots(true);
                      }}
                      className="input-field"
                      min={todayStr}
                    />
                  </div>

                  {date && (
                    <div className="slots-section">
                      <div className="section-eyebrow">Horários disponíveis</div>
                      <div className="section-title" style={{ fontSize: "20px", marginBottom: "16px" }}>
                        {formattedDate} — {formatDuracao(servicoSelecionado.duracao)}
                        {servicoSelecionado.buffer > 0 && (
                          <span style={{ fontSize: "14px", color: "var(--text-muted)" }}>
                            {" "}(+{servicoSelecionado.buffer}min de intervalo)
                          </span>
                        )}
                      </div>

                      {loadingSlots && (
                        <div className="slots-loading">
                          <span className="loading-dots">
                            <span /><span /><span />
                          </span>
                          <span style={{ marginLeft: "8px", color: "var(--text-muted)" }}>
                            Buscando horários disponíveis...
                          </span>
                        </div>
                      )}

                      {dataInfo?.closed && !loadingSlots && (
                        <div className="slots-empty">
                          <span style={{ fontSize: "32px" }}>😴</span>
                          <p>{dataInfo.message || "Fechado neste dia"}</p>
                          <p style={{ fontSize: "13px", color: "var(--text-muted)", marginTop: "4px" }}>
                            Escolha outra data para ver horários abertos.
                          </p>
                        </div>
                      )}

                      {slotsError && !loadingSlots && !dataInfo?.closed && (
                        <div className="slots-empty">
                          <span style={{ fontSize: "32px" }}>📅</span>
                          <p>{slotsError}</p>
                          {dataInfo && (
                            <p style={{ fontSize: "13px", color: "var(--text-muted)", marginTop: "4px" }}>
                              Funcionamento: {dataInfo.open} às {dataInfo.close}
                            </p>
                          )}
                        </div>
                      )}

                      {!loadingSlots && !dataInfo?.closed && availableSlots.length > 0 && visibleSlots.length === 0 && (
                        <div className="slots-empty">
                          <span style={{ fontSize: "32px" }}>⏳</span>
                          <p>Todos os horários de hoje já passaram.</p>
                          <p style={{ fontSize: "13px", color: "var(--text-muted)", marginTop: "4px" }}>
                            Por favor, selecione uma data futura para agendar.
                          </p>
                        </div>
                      )}

                      {!loadingSlots && !dataInfo?.closed && visibleSlots.length > 0 && (
                        <div className="slots-grid">
                          {visibleSlots.map((slot) => (
                            <button
                              key={slot}
                              type="button"
                              className={`slot-btn ${time === slot ? "selected" : ""}`}
                              onClick={() => {
                                setTime(slot);
                                setErrorMsg("");
                              }}
                            >
                              {slot}
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                  )}
                </>
              )}

              {servicoSelecionado && date && time && (
                <div className="summary-card" style={{ animationDelay: "0.1s" }}>
                  <div className="deco-line" />
                  <div style={{ marginBottom: "16px" }}>
                    <div className="section-eyebrow">Resumo do agendamento</div>
                  </div>
                  <div className="summary-row">
                    <span className="summary-label">Cliente</span>
                    <span className="summary-value">{nome} ({phone})</span>
                  </div>
                  <div className="summary-row">
                    <span className="summary-label">Serviço</span>
                    <span className="summary-value">{servicoSelecionado.nome}</span>
                  </div>
                  <div className="summary-row">
                    <span className="summary-label">Valor</span>
                    <span className="summary-value">
                      R$ {Number(servicoSelecionado.preco).toLocaleString("pt-BR", { minimumFractionDigits: 2 })}
                    </span>
                  </div>
                  <div className="summary-row">
                    <span className="summary-label">Data</span>
                    <span className="summary-value">{formattedDate}</span>
                  </div>
                  <div className="summary-row">
                    <span className="summary-label">Horário</span>
                    <span className="summary-value">{time}</span>
                  </div>
                  <div className="summary-row">
                    <span className="summary-label">Duração estimada</span>
                    <span className="summary-value">
                      {formatDuracao(servicoSelecionado.duracao)}
                      {servicoSelecionado.buffer > 0 && (
                        <span style={{ fontSize: "12px", color: "var(--text-muted)", marginLeft: "4px" }}>
                          (+{servicoSelecionado.buffer}min de intervalo)
                        </span>
                      )}
                    </span>
                  </div>
                </div>
              )}

              {errorMsg && (
                <div className="error-banner">
                  ⚠️ {errorMsg}
                </div>
              )}

              <div style={{ marginTop: "24px" }}>
                <button
                  type="button"
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
      </main>
    </div>
  );
}
