export interface User { name: string }
export type Id = string;
export function loadUser(id: Id): User { return { name: id } }
export const render = (u: User) => `<p>${u.name}</p>`;
export class View {}
const html = render(loadUser("x"));
