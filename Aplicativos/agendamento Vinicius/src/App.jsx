// src/App.jsx

import { useState, useEffect } from "react";

const API = "http://localhost:3001/api";

export default function App() {
  const [etapa, setEtapa] = useState(1);

  const [nome, setNome] = useState("");
  const [nomeInput, setNomeInput] = useState("");
  const [phone, setPhone] = useState("");

  const [servicoSelecionado, setServicoSelecionado] =
    useState(null);

  const [date, setDate] = useState("");
  const [time, setTime] = useState("");

  const [salvando, setSalvando] = useState(false);

  const servicos = [
    {
      id: 1,
      nome: "Corte + Sobrancelha",
      preco: 40,
      duracao: "1hr",
    },
    {
      id: 2,
      nome: "Corte & Barba",
      preco: 60,
      duracao: "1hr",
    },
    {
      id: 3,
      nome: "Corte",
      preco: 35,
      duracao: "1hr",
    },
    {
      id: 4,
      nome: "Barba",
      preco: 25,
      duracao: "30min",
    },
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
          color: "#6b7280",
        }),
      }).catch(() => {});
    });
  }, []);

  function enviarNome() {
    if (!nomeInput || !phone) return;

    setNome(nomeInput);
    setEtapa(2);
  }

  function ativarNotificacoes() {
    setEtapa(3);
  }

  function pularNotificacoes() {
    setEtapa(3);
  }

  async function buscarClientePorNome(nome) {
    const res = await fetch(`${API}/clients/`);
    const clients = await res.json();
    return clients.find(
      (c) => c.name.toLowerCase() === nome.toLowerCase()
    );
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

      setNome("");
      setNomeInput("");
      setPhone("");
      setServicoSelecionado(null);
      setDate("");
      setTime("");
      setEtapa(1);
    } catch (e) {
      alert("Erro ao salvar: " + e.message);
    }

    setSalvando(false);
  }

  return (
    <div className="min-h-screen bg-black text-white p-5">
      <div className="max-w-[1700px] mx-auto">
        {/* ETAPA 1 */}
        {etapa === 1 && (
          <div className="space-y-6">
            <div className="bg-[#050505] rounded-[22px] px-7 py-6 w-fit max-w-[1400px]">
              <p className="text-[32px] leading-relaxed">
                Olá, tudo bem? Sou a assistente virtual do(a)
                {" "}
                <span className="font-semibold">
                  Leandro THE BLESSED HAIR
                </span>
                {" "}
                e cuido do agendamento dos serviços dos
                profissionais dele(a), ok?
              </p>
            </div>

            <div className="bg-[#050505] rounded-[22px] px-7 py-6 w-fit">
              <p className="text-[32px]">
                Qual o seu nome? Escreva seu nome e
                sobrenome, por favor.
              </p>
            </div>

            <div className="pt-10 space-y-6">
              <input
                type="text"
                placeholder="Seu nome e sobrenome"
                value={nomeInput}
                onChange={(e) =>
                  setNomeInput(e.target.value)
                }
                className="
                  w-full
                  bg-[#202020]
                  rounded-[28px]
                  p-8
                  text-[34px]
                  outline-none
                  text-white
                  placeholder:text-zinc-500
                "
              />

              <input
                type="tel"
                placeholder="Seu telefone (com DDD)"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                className="
                  w-full
                  bg-[#202020]
                  rounded-[28px]
                  p-8
                  text-[34px]
                  outline-none
                  text-white
                  placeholder:text-zinc-500
                "
              />

              <button
                onClick={enviarNome}
                className="
                  w-full
                  bg-gradient-to-r
                  from-zinc-500
                  to-zinc-700
                  py-8
                  rounded-[28px]
                  text-[34px]
                  hover:opacity-90
                  transition
                "
              >
                Enviar
              </button>
            </div>
          </div>
        )}

        {/* ETAPA 2 */}
        {etapa === 2 && (
          <div className="space-y-8">
            <div className="flex justify-end">
              <div className="bg-zinc-300 text-black px-10 py-6 rounded-[28px] text-[30px]">
                {nome}
              </div>
            </div>

            <div className="bg-[#050505] rounded-[22px] px-7 py-6 w-fit">
              <p className="text-[32px]">
                Como vai, {nome}! Tudo bem?
              </p>
            </div>

            <div className="bg-[#050505] rounded-[22px] px-7 py-6 w-fit max-w-[1200px]">
              <p className="text-[32px] leading-relaxed">
                Para que possamos lembrá-lo de seu
                agendamento, ative suas notificações
                clicando abaixo:
              </p>
            </div>

            <div className="pt-10 space-y-6">
              <button
                onClick={ativarNotificacoes}
                className="
                  w-full
                  bg-gradient-to-r
                  from-zinc-500
                  to-zinc-700
                  py-8
                  rounded-[28px]
                  text-[34px]
                "
              >
                Ativar notificações
              </button>

              <button
                onClick={pularNotificacoes}
                className="
                  w-full
                  bg-[#111827]
                  py-8
                  rounded-[28px]
                  text-[34px]
                "
              >
                Pular
              </button>
            </div>
          </div>
        )}

        {/* ETAPA 3 */}
        {etapa === 3 && (
          <div className="space-y-10">
            <div className="bg-[#050505] rounded-[22px] px-7 py-6 w-fit">
              <p className="text-[32px]">
                Por qual serviço você está procurando?
              </p>
            </div>

            <div className="pt-10">
              <p className="text-[24px] text-zinc-300 mb-8">
                SELECIONE OS SERVIÇOS:
              </p>

              <div className="flex gap-5 overflow-x-auto pb-5">
                {servicos.map((item) => (
                  <div
                    key={item.id}
                    onClick={() =>
                      setServicoSelecionado(item)
                    }
                    className={`
                      min-w-[620px]
                      h-[320px]
                      rounded-[28px]
                      p-8
                      cursor-pointer
                      transition
                      border
                      ${
                        servicoSelecionado?.id === item.id
                          ? "border-white bg-[#1b1b1b]"
                          : "border-zinc-800 bg-[#202020]"
                      }
                    `}
                  >
                    <div className="flex justify-end">
                      <div
                        className={`
                          w-12
                          h-12
                          rounded-xl
                          ${
                            servicoSelecionado?.id ===
                            item.id
                              ? "bg-white"
                              : "bg-zinc-300"
                          }
                        `}
                      />
                    </div>

                    <div className="mt-32">
                      <h2 className="text-[40px] font-bold">
                        {item.nome}
                      </h2>

                      <div className="flex justify-between items-center mt-5">
                        <p className="text-[34px] text-zinc-400">
                          R$ {item.preco},00
                        </p>

                        <p className="text-[30px] text-zinc-400">
                          {item.duracao}
                        </p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>

              <div className="flex justify-between mt-6">
                <p className="text-zinc-500 text-[22px]">
                  ← ARRASTE PARA O LADO
                </p>

                <p className="text-zinc-500 text-[22px]">
                  PARA VER MAIS
                </p>
              </div>

              <div className="grid grid-cols-2 gap-6 mt-10">
                <div>
                  <label className="text-zinc-400 text-[20px] block mb-3">
                    Data
                  </label>
                  <input
                    type="date"
                    value={date}
                    onChange={(e) => setDate(e.target.value)}
                    className="
                      w-full
                      bg-[#202020]
                      rounded-[20px]
                      p-6
                      text-[28px]
                      outline-none
                      text-white
                      [color-scheme:dark]
                    "
                  />
                </div>
                <div>
                  <label className="text-zinc-400 text-[20px] block mb-3">
                    Horário
                  </label>
                  <input
                    type="time"
                    value={time}
                    onChange={(e) => setTime(e.target.value)}
                    className="
                      w-full
                      bg-[#202020]
                      rounded-[20px]
                      p-6
                      text-[28px]
                      outline-none
                      text-white
                      [color-scheme:dark]
                    "
                  />
                </div>
              </div>

              <button
                onClick={finalizarServico}
                disabled={salvando}
                className="
                  mt-6
                  w-full
                  bg-gradient-to-r
                  from-zinc-500
                  to-zinc-700
                  py-8
                  rounded-[28px]
                  text-[34px]
                  hover:opacity-90
                  transition
                  disabled:opacity-50
                "
              >
                {salvando ? "Salvando..." : "Enviar"}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}