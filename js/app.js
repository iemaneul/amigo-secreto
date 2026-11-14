import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { APP_CONFIG } from './config.js';

const SESSION_KEY = `${APP_CONFIG.localStorageKey}-participant`;
const appState = {
  credentials: null,
  portal: null
};

const elements = {
  authView: document.getElementById('authView'),
  appView: document.getElementById('appView'),
  loginForm: document.getElementById('loginForm'),
  authError: document.getElementById('authError'),
  logoutBtn: document.getElementById('logoutBtn'),
  welcomeTitle: document.getElementById('welcomeTitle'),
  resultName: document.getElementById('resultName'),
  revealButton: document.getElementById('revealButton'),
  receiverProfile: document.getElementById('receiverProfile'),
  profileForm: document.getElementById('profileForm'),
  profileMessage: document.getElementById('profileMessage'),
  drawStatusPill: document.getElementById('drawStatusPill'),
  navButtons: [...document.querySelectorAll('.nav-button')],
  panels: [...document.querySelectorAll('.panel')]
};

const supabase = createClient(APP_CONFIG.supabaseUrl, APP_CONFIG.supabaseAnonKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false
  }
});

function setPanel(panelId) {
  elements.panels.forEach((panel) => {
    panel.classList.toggle('hidden', panel.id !== panelId);
    panel.classList.toggle('active', panel.id === panelId);
  });

  elements.navButtons.forEach((button) => {
    button.classList.toggle('active', button.dataset.panel === panelId);
  });
}

function setMessage(element, text, type = 'success') {
  element.textContent = text;
  element.classList.remove('hidden', 'success', 'error');
  element.classList.add(type);
}

function normalizePhone(value) {
  return String(value || '').replace(/\D/g, '');
}

function getProfileValues() {
  return {
    favorite_color: document.getElementById('favoriteColor').value.trim(),
    hobbies: document.getElementById('hobbies').value.trim(),
    favorite_foods: document.getElementById('favoriteFoods').value.trim(),
    favorite_movies: document.getElementById('favoriteMovies').value.trim(),
    favorite_games: document.getElementById('favoriteGames').value.trim(),
    likes: document.getElementById('likes').value.trim(),
    dislikes: document.getElementById('dislikes').value.trim(),
    gift_suggestions: document.getElementById('giftSuggestions').value.trim(),
    notes: document.getElementById('notes').value.trim()
  };
}

function populateProfileForm(profile = {}) {
  document.getElementById('favoriteColor').value = profile.favorite_color || '';
  document.getElementById('hobbies').value = profile.hobbies || '';
  document.getElementById('favoriteFoods').value = profile.favorite_foods || '';
  document.getElementById('favoriteMovies').value = profile.favorite_movies || '';
  document.getElementById('favoriteGames').value = profile.favorite_games || '';
  document.getElementById('likes').value = profile.likes || '';
  document.getElementById('dislikes').value = profile.dislikes || '';
  document.getElementById('giftSuggestions').value = profile.gift_suggestions || '';
  document.getElementById('notes').value = profile.notes || '';
}

async function loadPortal(credentials) {
  const { data, error } = await supabase.rpc('participant_portal_login', {
    p_phone: credentials.phone,
    p_password: credentials.password
  });

  if (error) {
    throw error;
  }

  if (!data?.participant) {
    throw new Error('Credenciais inválidas.');
  }

  appState.credentials = credentials;
  appState.portal = data;
  populateProfileForm(data.own_profile);
  renderApp();
}

function renderReceiverProfile() {
  const { receiver, receiver_profile: profile } = appState.portal;

  if (!receiver) {
    elements.receiverProfile.textContent = 'O perfil ficará disponível depois do sorteio.';
    elements.receiverProfile.classList.add('empty-state');
    return;
  }

  if (!profile || Object.values(profile).every((value) => !value)) {
    elements.receiverProfile.textContent = 'Este participante ainda não preencheu o perfil.';
    elements.receiverProfile.classList.add('empty-state');
    return;
  }

  const items = [
    { label: 'Nome', value: receiver.display_name },
    { label: 'Cor favorita', value: profile.favorite_color },
    { label: 'Hobbies', value: profile.hobbies },
    { label: 'Comidas favoritas', value: profile.favorite_foods },
    { label: 'Filmes e séries', value: profile.favorite_movies },
    { label: 'Jogos favoritos', value: profile.favorite_games },
    { label: 'Gosta', value: profile.likes },
    { label: 'Não gosta', value: profile.dislikes },
    { label: 'Sugestões de presentes', value: profile.gift_suggestions },
    { label: 'Observações', value: profile.notes }
  ].filter((item) => item.value);

  elements.receiverProfile.classList.remove('empty-state');
  const metaList = document.createElement('div');
  metaList.className = 'meta-list';

  items.forEach((item) => {
    const profileItem = document.createElement('div');
    profileItem.className = 'profile-item';
    const label = document.createElement('strong');
    label.textContent = item.label;
    const value = document.createElement('span');
    value.textContent = item.value;
    profileItem.append(label, value);
    metaList.append(profileItem);
  });

  elements.receiverProfile.replaceChildren(metaList);
}

function renderDashboard() {
  const { draw_completed: drawCompleted, receiver } = appState.portal;
  const revealed = sessionStorage.getItem(`secret-reveal-${appState.portal.participant.id}`) === 'true';

  if (!drawCompleted) {
    elements.drawStatusPill.textContent = 'Aguardando';
    elements.resultName.textContent = '—';
    elements.revealButton.disabled = true;
    elements.revealButton.textContent = 'Aguarde o sorteio';
    elements.receiverProfile.textContent = 'O sorteio ainda não foi concluído.';
    elements.receiverProfile.classList.add('empty-state');
    return;
  }

  elements.drawStatusPill.textContent = 'Concluído';

  if (!receiver) {
    elements.resultName.textContent = 'Sem resultado';
    elements.revealButton.disabled = true;
    elements.revealButton.textContent = 'Resultado indisponível';
    elements.receiverProfile.textContent = 'Não foi possível carregar o resultado.';
    elements.receiverProfile.classList.add('empty-state');
    return;
  }

  elements.revealButton.disabled = revealed;
  elements.revealButton.textContent = revealed ? 'Resultado revelado' : 'Revelar meu amigo secreto';
  elements.resultName.textContent = revealed ? receiver.display_name : '🎁';

  if (revealed) {
    renderReceiverProfile();
  } else {
    elements.receiverProfile.textContent = 'Revele o resultado para ver as preferências do perfil.';
    elements.receiverProfile.classList.add('empty-state');
  }
}

function renderApp() {
  elements.welcomeTitle.textContent = `Olá, ${appState.portal.participant.display_name}!`;
  elements.authView.classList.add('hidden');
  elements.appView.classList.remove('hidden');
  setPanel('dashboardPanel');
  renderDashboard();
}

async function handleLogin(event) {
  event.preventDefault();
  const formData = new FormData(event.currentTarget);
  const credentials = {
    phone: normalizePhone(formData.get('phone')),
    password: String(formData.get('password') || '')
  };

  if (!credentials.phone || !credentials.password) {
    setMessage(elements.authError, 'Informe o celular e a senha.', 'error');
    return;
  }

  try {
    await loadPortal(credentials);
    sessionStorage.setItem(SESSION_KEY, JSON.stringify(credentials));
    elements.authError.classList.add('hidden');
    elements.loginForm.reset();
  } catch (error) {
    console.error(error);
    setMessage(elements.authError, 'Celular ou senha inválidos.', 'error');
  }
}

function handleReveal() {
  if (!appState.portal?.receiver) return;

  sessionStorage.setItem(`secret-reveal-${appState.portal.participant.id}`, 'true');
  renderDashboard();
}

function handleLogout() {
  sessionStorage.removeItem(SESSION_KEY);
  appState.credentials = null;
  appState.portal = null;
  elements.appView.classList.add('hidden');
  elements.authView.classList.remove('hidden');
  elements.loginForm.reset();
  elements.profileForm.reset();
  elements.authError.classList.add('hidden');
  elements.profileMessage.classList.add('hidden');
}

async function handleProfileSave(event) {
  event.preventDefault();

  try {
    const { error } = await supabase.rpc('participant_profile_save', {
      p_phone: appState.credentials.phone,
      p_password: appState.credentials.password,
      p_profile: getProfileValues()
    });

    if (error) throw error;

    appState.portal.own_profile = getProfileValues();
    setMessage(elements.profileMessage, 'Perfil atualizado com sucesso.', 'success');
  } catch (error) {
    console.error(error);
    setMessage(elements.profileMessage, 'Não foi possível salvar o perfil. Entre novamente e tente de novo.', 'error');
  }
}

async function initializeApp() {
  const savedCredentials = sessionStorage.getItem(SESSION_KEY);

  if (!savedCredentials) {
    elements.authView.classList.remove('hidden');
    elements.appView.classList.add('hidden');
    return;
  }

  try {
    await loadPortal(JSON.parse(savedCredentials));
  } catch (error) {
    console.error(error);
    sessionStorage.removeItem(SESSION_KEY);
    elements.authView.classList.remove('hidden');
    elements.appView.classList.add('hidden');
    setMessage(elements.authError, 'Sua sessão expirou. Entre novamente.', 'error');
  }
}

function attachListeners() {
  elements.loginForm.addEventListener('submit', handleLogin);
  elements.logoutBtn.addEventListener('click', handleLogout);
  elements.revealButton.addEventListener('click', handleReveal);
  elements.profileForm.addEventListener('submit', handleProfileSave);

  elements.navButtons.forEach((button) => {
    button.addEventListener('click', () => setPanel(button.dataset.panel));
  });

  if (window.lucide) {
    window.lucide.createIcons();
  }
}

attachListeners();
initializeApp();
