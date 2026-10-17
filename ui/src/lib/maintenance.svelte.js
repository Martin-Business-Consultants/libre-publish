// Whether the CMS answered "maintenance" (503): an imported backup is
// replacing the site. The admin says so until a request gets through.
class Maintenance {
  on = $state(false);
}

export const maintenance = new Maintenance();
