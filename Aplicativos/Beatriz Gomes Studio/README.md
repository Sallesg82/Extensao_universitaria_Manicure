# 🌸 Beatriz Gomes Studio — Portal de Agendamento Online

Portal de autoatendimento responsivo para clientes realizarem agendamentos de serviços de manicure, pedicure e estética em tempo real. Integrado diretamente à API do CRM BeautyFlow.

---

## 📋 Visão Geral

O aplicativo proporciona uma experiência conversacional guiada tipo assistente virtual, estruturada em 3 etapas progressivas:

1. **Identificação**: Coleta do nome completo e telefone/WhatsApp da cliente.
2. **Preferências**: Opt-in para notificações e lembretes automáticos.
3. **Agendamento**:
   - Carrossel dinâmico com o catálogo de serviços direto do CRM.
   - Calendário interativo com bloqueio de datas passadas e dias de folga.
   - Consulta inteligente de horários disponíveis (`/api/available-slots`), calculando duração, margens de buffer e evitando colisões de horários.
   - Modal comemorativo de confirmação com envio de notificação WebSocket para a agenda do profissional.

---

## 🛠 Tecnologias Utilizadas

* **React 19**: Interface reativa baseada em componentes funcionais.
* **Vite 8**: Servidor de desenvolvimento rápido e bundler de produção.
* **Tailwind CSS 4**: Estilização moderna e responsiva com micro-animações.
* **Socket.IO Client**: Conexão bidirecional com o backend Flask do CRM.

---

## ⚙️ Variáveis de Ambiente

Crie ou edite o arquivo `.env` na raiz desta pasta:

```env
VITE_API_URL=http://localhost:3001/api
```

> **Nota para deploy ou acesso via rede local (Wi-Fi):**
> Substitua `localhost` pelo endereço de IP da máquina servidora (ex: `http://192.168.1.15:3001/api`). Em builds de produção com Docker, o valor é passado automaticamente via argumento de build pelo instalador.

---

## 🚀 Como Executar em Desenvolvimento

```bash
# 1. Instalar dependências
npm install

# 2. Executar em modo desenvolvimento
npm run dev

# → Acesso local: http://localhost:5173
```

---

## 📦 Build para Produção

```bash
npm run build
```

Os arquivos estáticos otimizados serão gerados na pasta `dist/` e podem ser servidos por qualquer servidor HTTP como Nginx ou Caddy.

