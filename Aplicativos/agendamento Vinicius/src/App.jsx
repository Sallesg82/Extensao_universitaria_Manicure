// src/App.jsx

import { useState } from "react";

export default function App() {
  const [etapa, setEtapa] = useState(1);

  const [nome, setNome] = useState("");
  const [nomeInput, setNomeInput] = useState("");

  const [servicoSelecionado, setServicoSelecionado] =
    useState(null);

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

  function enviarNome() {
    if (!nomeInput) return;

    setNome(nomeInput);
    setEtapa(2);
  }

  function ativarNotificacoes() {
    setEtapa(3);
  }

  function pularNotificacoes() {
    setEtapa(3);
  }

  function finalizarServico() {
    if (!servicoSelecionado) return;

    alert(
      `Agendamento iniciado para ${nome}\nServiço: ${servicoSelecionado.nome}`
    );
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

            <div className="pt-10">
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

              <button
                onClick={enviarNome}
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

              <button
                onClick={finalizarServico}
                className="
                  mt-10
                  w-full
                  bg-gradient-to-r
                  from-zinc-500
                  to-zinc-700
                  py-8
                  rounded-[28px]
                  text-[34px]
                "
              >
                Enviar
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}