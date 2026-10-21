# Referência Completa de Rotas da API e WebSocket

Esta documentação fornece a especificação técnica de todas as rotas HTTP e eventos WebSocket expostos pelo backend em **Rust** do **BeautyFlow CRM**.

Todas as rotas da API estão sob o prefixo `/api`.

---

## 1. Autenticação e Usuários

| Método | Rota | Descrição | Payload / Resposta |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/users/exists` | Verifica se existem usuários cadastrados | `{"exists": bool}` |
| `POST`| `/api/users/login` | Autentica um usuário (por email ou username) | **Body:** `{"email": "...", "password": "..."}`<br>**Retorno:** Objeto `UserDto` com dados do operador |
| `GET` | `/api/users` | Lista todos os usuários | Lista de `UserDto` |
| `POST`| `/api/users` | Cria um novo usuário | **Body:** `{"name": "...", "email": "...", "password": "...", "phone": "...", "role": "..."}` |
| `GET` | `/api/users/{id}` | Obtém dados de um usuário por ID | Objeto `UserDto` |
| `PUT` | `/api/users/{id}` | Atualiza dados cadastrais de um usuário | Dados parciais a atualizar |
| `DELETE`| `/api/users/{id}`| Exclui um usuário | `{"message": "Usuário removido", "id": int}` |
| `PUT` | `/api/users/{id}/password` | Altera a senha de um usuário | **Body:** `{"password": "..."}` |

---

## 2. Dashboard e Estatísticas Financeiras

| Método | Rota | Descrição | Payload / Resposta |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/stats` | Agregação completa de métricas financeiras | Receita de hoje, receita do mês, despesas do mês, saldo, ticket médio, histórico diário/semanal, top clientes, taxa de retorno |

---

## 3. Clientes

| Método | Rota | Descrição | Payload / Resposta |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/clients` | Lista clientes com total de visitas e gastos | Lista de clientes com campos calculados `total_visits`, `total_spent`, `last_visit` |
| `POST`| `/api/clients` | Cadastra um novo cliente | **Body:** `{"name": "...", "phone": "...", "email": "...", "cpf": "...", "notes": "..."}` |
| `GET` | `/api/clients/{id}`| Detalhes de um cliente | Objeto do cliente |
| `PUT` | `/api/clients/{id}`| Atualiza cadastro do cliente | Objeto atualizado |
| `DELETE`| `/api/clients/{id}`| Remove um cliente | Confirmação de exclusão |

---

## 4. Agendamentos

| Método | Rota | Descrição | Payload / Resposta |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/appointments` | Lista agendamentos com filtros | Aceita query params `date`, `month`, `client_id`, `status` |
| `POST`| `/api/appointments` | Cria agendamento com validação | Verifica conflito de horários e horário comercial; dispara webhook n8n |
| `GET` | `/api/appointments/{id}`| Detalhes de um agendamento | Objeto completo do agendamento com dados do cliente e serviço |
| `PUT` | `/api/appointments/{id}`| Atualiza agendamento | Atualiza data/hora, status (`confirmed`, `done`, `cancelled`), reconcilia transação financeira automaticamente |
| `DELETE`| `/api/appointments/{id}`| Cancela/remove agendamento | Remove e reverte transação se existente |

---

## 5. Serviços

| Método | Rota | Descrição | Payload / Resposta |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/services` | Lista serviços ativos | Retorna catálogo de procedimentos, preços, durações e buffers |
| `POST`| `/api/services` | Adiciona serviço | **Body:** `{"name": "...", "price": float, "duration": int, "buffer": int, "category": "...", "color": "..."}` |
| `GET` | `/api/services/{id}` | Busca serviço por ID | Detalhes do serviço |
| `PUT` | `/api/services/{id}` | Edita serviço | Dados atualizados |
| `DELETE`| `/api/services/{id}` | Remove serviço | Confirmação |

---

## 6. Estoque e Produtos

| Método | Rota | Descrição | Payload / Resposta |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/products` | Lista produtos com filtros | Filtros por categoria, status (`in_stock`, `low_stock`, `out_of_stock`) |
| `GET` | `/api/products/stats` | KPIs e valor total do estoque | `total_products`, `total_units`, `total_value`, contagem por status |
| `POST`| `/api/products` | Cadastra novo produto | Nome, categoria, quantidade, preço unitário, estoque mínimo |
| `GET` | `/api/products/{id}` | Detalhes do produto | Dados do item |
| `PUT` | `/api/products/{id}` | Atualiza produto | Atualização completa dos campos |
| `PATCH`| `/api/products/{id}/stock`| Ajuste rápido de estoque | **Body:** `{"qty": int}` ou `{"delta": int}` |
| `DELETE`| `/api/products/{id}`| Remove produto | Confirmação |

---

## 7. Horários e Disponibilidade

| Método | Rota | Descrição | Payload / Resposta |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/business-hours` | Horários de funcionamento semanais | Grade de Seg-Dom com horários de abertura e fechamento |
| `PUT` | `/api/business-hours` | Atualiza horários de funcionamento | Grade semanal atualizada |
| `GET` | `/api/available-slots` | Slots de horários livres por dia | **Query:** `?date=YYYY-MM-DD&service_id=X`. Retorna lista de horários calculados considerando agendamentos existentes |

---

## 8. Configurações e Categorias de Despesas

| Método | Rota | Descrição | Payload / Resposta |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/settings` | Obtém todas as configurações | Dicionário chave-valor (`meta_mensal`, nome da empresa, etc.) |
| `PUT` | `/api/settings` | Salva configurações | Objeto com chaves a atualizar |
| `GET` | `/api/expense-categories` ou `/api/settings/expense-categories` | Lista categorias de despesas | Lista de categorias (`[{"id": "1", "name": "..."}]`) |
| `POST`| `/api/expense-categories` | Cria categoria de despesa | **Body:** `{"name": "..."}` |

---

## 9. Transações Financeiras

| Método | Rota | Descrição | Payload / Resposta |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/transactions` | Lista movimentações financeiras | Suporta filtros `type` (`income`/`expense`), `month`, `category` |
| `POST`| `/api/transactions` | Cria lançamento financeiro avulso | Emite notificação WebSocket em tempo real para a interface |
| `DELETE`| `/api/transactions/{id}` | Remove transação financeira | Reverte lançamento |

---

## 10. Metas Mensais

| Método | Rota | Descrição | Payload / Resposta |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/metas` | Lista metas mensais cadastradas | Lista de metas por mês (`YYYY-MM`) |
| `POST`| `/api/metas` | Define/atualiza meta mensal | **Body:** `{"mes": "YYYY-MM", "meta": float}` (executa UPSERT) |

---

## 11. Notificações

| Método | Rota | Descrição | Payload / Resposta |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/notifications` | Lista notificações do sistema | Alertas de estoque, metas e agendamentos |
| `GET` | `/api/notifications/unread-count`| Contagem de não lidas | `{"unread": int}` |
| `PUT` | `/api/notifications/{id}/read` | Marca uma notificação como lida | Atualiza registro |
| `POST`| `/api/notifications/read-all` | Marca todas as notificações como lidas | Confirmação |

---

## 12. WhatsApp (WAHA) & Mensagens

| Método | Rota | Descrição |
| :--- | :--- | :--- |
| `GET` | `/api/whatsapp/status` | Status da conexão do WhatsApp |
| `GET` | `/api/whatsapp/qr` | QR Code em SVG/Base64 para escaneamento |
| `POST`| `/api/whatsapp/refresh-qr` | Força geração de novo QR Code |
| `GET` | `/api/whatsapp/screenshot` | Proxy de captura de tela da sessão WAHA |
| `POST`| `/api/whatsapp/start` | Inicia a sessão no WAHA |
| `POST`| `/api/whatsapp/logout` | Desconecta a sessão ativa |
| `POST`| `/api/whatsapp/disconnect` | Desconecta e remove sessão |
| `POST`| `/api/whatsapp/test` | Envia mensagem de teste |
| `POST`| `/api/whatsapp/send-notification`| Envia notificação estruturada com template |
| `POST`| `/api/whatsapp/send-pending-reminders` | Dispara verificação de lembretes manuais |
| `GET` | `/api/whatsapp/chat/messages` | Consulta histórico de chat por telefone |
| `POST`| `/api/whatsapp/chat/send` | Envia mensagem no chat e armazena em SQLite |
| `POST`| `/api/whatsapp/chat/sync` | Sincroniza mensagens do WAHA para o banco local |
| `GET` | `/api/whatsapp/chat/canned-responses` | Lista respostas rápidas |
| `GET` | `/api/whatsapp/chat/conversations` | Lista últimas conversas ativas |
| `POST`| `/api/whatsapp/webhook` | Webhook de entrada de mensagens do WAHA |

---

## 13. n8n & Google Calendar

| Método | Rota | Descrição |
| :--- | :--- | :--- |
| `GET` | `/api/n8n/config` | Exibe configurações do n8n |
| `GET` | `/api/n8n/status` | Checa conectividade do webhook n8n |
| `POST`| `/api/n8n/webhook/test` | Envia evento de teste para o n8n |
| `POST`| `/api/n8n/sync-calendar` | Dispara sincronização em lote de agendamentos |

---

## 14. Eventos WebSocket (Socket.IO v4)

O servidor Rust implementa Socket.IO nativo via `socketioxide` no namespace padrão `/`:

| Nome do Evento | Origem | Descrição |
| :--- | :--- | :--- |
| `appointment_created` | Backend ➔ Frontend | Notifica novo agendamento inserido |
| `appointment_updated` | Backend ➔ Frontend | Notifica alteração de status, horário ou cancelamento |
| `transaction_created` | Backend ➔ Frontend | Notifica novo faturamento ou despesa lançada |
| `transaction_updated` | Backend ➔ Frontend | Notifica edição de transação |
| `client_updated` | Backend ➔ Frontend | Notifica cadastro ou atualização de cliente |
| `stock_updated` | Backend ➔ Frontend | Notifica alteração de quantidade no estoque |
| `new_message` | Backend ➔ Frontend | Notifica recebimento ou envio de mensagem no WhatsApp |
| `notification_created` | Backend ➔ Frontend | Notifica surgimento de alerta na interface |
