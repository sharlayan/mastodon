const normalizeLanguage = (language) => language || 'und';
const acceptsLanguage = (chosenLanguages, language) => !Array.isArray(chosenLanguages) || chosenLanguages.includes(normalizeLanguage(language));

export { acceptsLanguage, normalizeLanguage };
