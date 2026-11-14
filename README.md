# Amigo Secreto 2026

Aplicação web para nove participantes. Cada pessoa entra com o próprio celular e senha, vê somente seu resultado e pode preencher as preferências do perfil.

## Publicar no GitHub Pages

1. Em **Settings → Pages**, selecione **Deploy from a branch**, a branch `main` e a pasta `/ (root)`.
2. Em `js/config.js`, configure a URL do Supabase e a chave pública `publishable`.
3. Use o link de Pages exibido pelo GitHub para abrir o app.

Não habilite Supabase Auth ou Phone/SMS, nem publique Edge Functions. O login e o salvamento do perfil usam funções RPC no banco; as senhas são armazenadas como hashes.

## Banco de dados

O schema é `sql/secret-friend-schema.sql`. Os arquivos `sql/seed-official-participants.sql` e `sql/participant-passwords.sql` contêm celulares e senhas privadas e são intencionalmente ignorados pelo Git. Execute esses arquivos somente no SQL Editor do seu projeto Supabase; nunca os publique.

Depois de carregar os participantes, as restrições e as senhas no banco, execute `select public.run_secret_draw();` uma única vez. A função salva o sorteio sem retornar os pares.
